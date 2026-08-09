#!/usr/bin/env python3
"""Run the Shapearator engine for MacShapearator and report over stdout.

Protocol -- one JSON object per line, tab-separated from its tag:

    PREFLIGHT<TAB>{"ok": bool, "provider": str, "message": str, ...}
    PROGRESS<TAB>{"phase": str, "current": int, "total": int, "message": str}
    RESULT<TAB>{"icons": [...], "naming": {...}, "commit": {...}, "warnings": [...]}
    ERROR<TAB>{"kind": str, "message": str}

Every failure is reported as an ERROR line so the app can show the engine's own
actionable text; a Python traceback must never reach the user interface.
"""
from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--settings", required=True, type=Path)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--formats", nargs="+", default=["png", "svg"])
    parser.add_argument(
        "--allow-unnamed",
        action="store_true",
        help="Export with generic filenames if the vision backend is unavailable.",
    )
    parser.add_argument(
        "--preview-dir",
        type=Path,
        default=None,
        help="Where to render UI thumbnails. Defaults to a temporary directory; "
             "never write these into the user's export folder.",
    )
    return parser.parse_args()


def emit(tag: str, payload: dict) -> None:
    print(f"{tag}\t" + json.dumps(payload, ensure_ascii=True), flush=True)


# Swift sends camelCase; the engine's schema is snake_case. Only the spelling is
# translated here -- validation and defaults belong to services.settings_schema,
# so a field the app does not know about cannot break loading.
_FIELD_ALIASES = {
    "ollamaURL": "ollama_url",
    "ollamaModel": "ollama_model",
    "llamacppURL": "llamacpp_url",
    "llamacppModel": "llamacpp_model",
    "localModelRoot": "local_model_root",
    "localModelName": "local_model_name",
    "modelsRoot": "models_root",
    "semanticNaming": "semantic_naming",
    "defaultFormats": "default_formats",
    "outputWidth": "output_width",
    "outputHeight": "output_height",
    "canvasMode": "canvas_mode",
    "bitmapExportMode": "bitmap_export_mode",
    "minArea": "min_area",
    "mergeGap": "merge_gap",
    "lastInputPath": "last_input_path",
    "lastOutputDir": "last_output_dir",
}

# App-only settings the engine has no opinion about.
_APP_ONLY_KEYS = {"backendRoot", "pythonPath"}


def build_settings(raw: dict, input_path: Path, output_dir: Path):
    """Translate the app's settings into a validated AppSettings."""
    from services.settings_schema import coerce_settings

    translated = {
        _FIELD_ALIASES.get(key, key): value
        for key, value in raw.items()
        if key not in _APP_ONLY_KEYS
    }
    translated["last_input_path"] = str(input_path)
    translated["last_output_dir"] = str(output_dir)

    result = coerce_settings(translated)
    for warning in result.warnings:
        emit("PROGRESS", {"phase": "settings", "current": 0, "total": 1, "message": warning})
    return result.settings


def icon_record(icon, preview_dir: Path, export_svg_to_png) -> dict:
    """Describe one icon for the UI, rendering a thumbnail if it has no bitmap."""
    preview_path = str(icon.preview_path) if icon.preview_path else None
    if preview_path is None and "svg" in icon.outputs:
        preview_dir.mkdir(parents=True, exist_ok=True)
        generated = preview_dir / f"{icon.stem}.png"
        try:
            export_svg_to_png(icon.outputs["svg"], generated)
            preview_path = str(generated)
        except Exception:
            preview_path = None
    return {
        "index": icon.index,
        "stem": icon.stem,
        "outputs": {fmt: str(path) for fmt, path in icon.outputs.items()},
        "previewPath": preview_path,
        "canvasSize": list(icon.canvas_size),
        "sourceSize": list(icon.source_size),
        "sourceBounds": list(icon.source_bounds),
        "metadataPath": str(icon.metadata_path) if icon.metadata_path else None,
        "namingStatus": icon.naming_status,
        "namingError": icon.naming_error,
        "semanticTags": icon.semantic_tags or [],
        "semanticConfidence": icon.semantic_confidence,
    }


def run(args: argparse.Namespace, backend_root: Path) -> int:
    from services.extractor import IconExtractor
    from services.extraction_types import ExtractionProgress  # noqa: F401  (documents the payload)
    from services.semantic_naming import SemanticPreflightError, naming_requested
    from services.svg_ops import export_svg_to_png
    from services.vision import preflight

    raw = json.loads(args.settings.read_text(encoding="utf-8"))
    input_path = args.input.resolve()
    output_dir = args.output.resolve()
    settings = build_settings(raw, input_path, output_dir)

    # Report readiness before extracting so the app can offer a real choice
    # rather than discovering the problem through a failure.
    if naming_requested(settings):
        check = preflight(settings)
        emit("PREFLIGHT", {
            "ok": check.ok,
            "provider": check.provider,
            "message": check.message,
            "model": check.model,
            "visionCapable": check.vision_capable,
        })

    def on_progress(progress) -> None:
        emit("PROGRESS", {
            "phase": progress.phase,
            "current": progress.current,
            "total": progress.total,
            "message": progress.message,
        })

    try:
        result = IconExtractor(settings).extract(
            input_path,
            output_dir,
            set(args.formats),
            progress_callback=on_progress,
            allow_unnamed=args.allow_unnamed,
        )
    except SemanticPreflightError as exc:
        emit("ERROR", {
            "kind": "preflight",
            "message": str(exc),
            "provider": exc.result.provider,
            "recoverable": True,
        })
        return 2
    except OSError as exc:
        emit("ERROR", {"kind": "extraction", "message": _describe_os_error(exc, output_dir)})
        return 1
    except Exception as exc:
        emit("ERROR", {"kind": "extraction", "message": str(exc) or exc.__class__.__name__})
        return 1

    preview_dir = args.preview_dir or Path(tempfile.mkdtemp(prefix="macshapearator_previews_"))
    emit("RESULT", {
        "inputPath": str(result.input_path),
        "outputDir": str(result.output_dir),
        "providerSummary": result.provider_summary,
        "engineVersion": _engine_version(backend_root),
        "icons": [icon_record(icon, preview_dir, export_svg_to_png) for icon in result.icons],
        "naming": {
            "requested": result.naming.requested,
            "provider": result.naming.provider,
            "model": result.naming.model,
            "named": result.naming.named,
            "failed": result.naming.failed,
            "errors": list(result.naming.errors),
            "summary": result.naming.describe(),
        },
        "commit": {
            "written": result.commit.written if result.commit else 0,
            "replaced": result.commit.replaced if result.commit else 0,
            "preserved": result.commit.preserved if result.commit else 0,
        },
        "warnings": list(result.warnings),
    })
    return 0


# macOS gates these behind a privacy prompt. A denied app does not get a clean
# "permission denied": writes fail as if the path simply were not there.
_PROTECTED_FOLDERS = ("Desktop", "Documents", "Downloads")


def _describe_os_error(exc: OSError, output_dir: Path) -> str:
    """Turn a bare errno into something the user can act on."""
    base = str(exc) or exc.__class__.__name__
    try:
        relative = output_dir.resolve().relative_to(Path.home())
        protected = relative.parts and relative.parts[0] in _PROTECTED_FOLDERS
    except (ValueError, OSError):
        protected = False
    if protected:
        return (
            f"{base}\n\nmacOS may be blocking access to your "
            f"{output_dir.resolve().relative_to(Path.home()).parts[0]} folder. "
            "Grant MacShapearator access in System Settings > Privacy & Security > "
            "Files and Folders, or choose an output folder elsewhere."
        )
    return base


def _engine_version(backend_root: Path) -> str:
    stamp = backend_root / "ENGINE_VERSION"
    if stamp.is_file():
        return stamp.read_text(encoding="utf-8").strip()
    try:
        from services.extractor import APP_VERSION

        return APP_VERSION
    except Exception:
        return "unknown"


def main() -> int:
    args = parse_args()
    try:
        raw = json.loads(args.settings.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        emit("ERROR", {"kind": "settings", "message": f"Could not read settings: {exc}"})
        return 1

    backend_root = Path(raw.get("backendRoot", "")).resolve()
    if not (backend_root / "services" / "extractor.py").is_file():
        emit("ERROR", {
            "kind": "backend",
            "message": f"No Shapearator engine at {backend_root}. Rebuild the app with build_app.sh.",
        })
        return 1
    if str(backend_root) not in sys.path:
        sys.path.insert(0, str(backend_root))

    try:
        return run(args, backend_root)
    except Exception as exc:  # a traceback must never reach the UI
        emit("ERROR", {"kind": "internal", "message": f"{exc.__class__.__name__}: {exc}"})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
