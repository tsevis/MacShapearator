#!/usr/bin/env python3
"""Expose the Shapearator engine's non-extraction services to MacShapearator.

Everything here is a thin projection of engine APIs into the same line protocol
`extract_bridge.py` uses. Nothing is reimplemented: backend readiness comes from
`services.vision.preflight`, model discovery from `services.model_registry` and
`services.llamacpp_models`, and setup from `services.first_run`. That way the
Mac app gains both backends, and future engine work, for free.

    engine_bridge.py preflight     --settings S            -> PREFLIGHT
    engine_bridge.py models        --settings S            -> MODELS
    engine_bridge.py setup-status  --settings S            -> SETUP
    engine_bridge.py install       --settings S --key K --backend B
                                                           -> PROGRESS…, INSTALLED
    engine_bridge.py start-server  --settings S --key K     -> SERVER

Failures are reported as an ERROR line, never a traceback.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def emit(tag: str, payload: dict) -> None:
    print(f"{tag}\t" + json.dumps(payload, ensure_ascii=True), flush=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "command",
        choices=["preflight", "models", "setup-status", "install", "start-server"],
    )
    parser.add_argument("--settings", required=True, type=Path)
    parser.add_argument("--key", default="", help="Model catalog key, for install/start-server.")
    parser.add_argument("--backend", default="", choices=["", "ollama", "llamacpp"])
    return parser.parse_args()


def load_settings(raw: dict):
    """Build a validated AppSettings from the app's camelCase payload."""
    from services.settings_schema import coerce_settings

    aliases = {
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
    app_only = {"backendRoot", "pythonPath"}
    translated = {aliases.get(k, k): v for k, v in raw.items() if k not in app_only}
    return coerce_settings(translated).settings


def describe_model(model) -> dict:
    return {
        "name": model.name,
        "source": model.source,
        "location": model.location,
        "priority": model.priority,
        "recommendation": model.recommendation,
        "supportsVision": model.supports_vision,
    }


def cmd_preflight(settings) -> int:
    from services.vision import preflight

    result = preflight(settings)
    emit("PREFLIGHT", {
        "ok": result.ok,
        "provider": result.provider,
        "message": result.message,
        "model": result.model,
        "visionCapable": result.vision_capable,
    })
    return 0


def cmd_models(settings) -> int:
    from services.first_run import detect_backends
    from services.llamacpp_models import available_startable_models
    from services.model_registry import ModelRegistry

    registry = ModelRegistry()
    status = detect_backends(settings)
    startable = available_startable_models(settings.models_root)
    emit("MODELS", {
        "backends": {
            "ollamaReachable": status.ollama_reachable,
            "llamacppBinary": status.llamacpp_binary,
        },
        "ollama": [describe_model(m) for m in registry.list_ollama_models()],
        "llamacpp": [describe_model(m) for m in registry.list_llamacpp_models(settings.llamacpp_url)],
        "llamacppStartable": [
            {"displayName": m.display_name, "priority": m.priority, "source": m.source}
            for m in startable
        ],
        "directory": [describe_model(m) for m in registry.list_directory_models(settings.local_model_root)],
    })
    return 0


def cmd_setup_status(settings) -> int:
    from services.first_run import build_candidates, detect_backends, is_setup_marked, needs_first_run

    status = detect_backends(settings)
    candidates = build_candidates(settings, status)
    emit("SETUP", {
        "backends": {
            "ollamaReachable": status.ollama_reachable,
            "llamacppBinary": status.llamacpp_binary,
        },
        "setupMarked": is_setup_marked(),
        "needsFirstRun": needs_first_run(settings),
        "candidates": [
            {
                "key": c.spec.key,
                "displayName": c.spec.display_name,
                "recommendation": c.spec.recommendation,
                "backend": c.backend,
                "installed": c.installed,
                "approxGB": c.approx_gb,
                "defaultSelected": c.default_selected,
                "label": c.label,
            }
            for c in candidates
        ],
    })
    return 0


def cmd_install(settings, key: str, backend: str) -> int:
    from services.first_run import apply_active_model, build_candidates, install_candidate, mark_setup_complete

    if not key or not backend:
        emit("ERROR", {"kind": "usage", "message": "install requires --key and --backend."})
        return 1

    match = next(
        (c for c in build_candidates(settings) if c.spec.key == key and c.backend == backend),
        None,
    )
    if match is None:
        emit("ERROR", {
            "kind": "install",
            "message": f"'{key}' is not available on {backend}. The backend may not be running.",
        })
        return 1

    def on_progress(progress) -> None:
        emit("PROGRESS", {
            "backend": progress.backend,
            "modelKey": progress.model_key,
            "phase": progress.phase,
            "completed": progress.completed,
            "total": progress.total,
            "fraction": progress.fraction,
            "message": progress.message,
        })

    install_candidate(settings, match, on_progress)
    updated = apply_active_model(settings, match)
    mark_setup_complete({"installed": [key], "backend": backend})
    emit("INSTALLED", {
        "key": key,
        "backend": backend,
        "provider": updated.provider,
        "ollamaModel": updated.ollama_model,
        "llamacppModel": updated.llamacpp_model,
        "semanticNaming": updated.semantic_naming,
    })
    return 0


def cmd_start_server(settings, key: str) -> int:
    """Start llama-server for a downloaded or cached model, if one is available."""
    from services.llamacpp_models import available_startable_models
    from services.llamacpp_server import LlamaCppServerManager, is_server_healthy

    if is_server_healthy(settings.llamacpp_url):
        emit("SERVER", {"running": True, "message": "llama.cpp server is already running."})
        return 0

    models = available_startable_models(settings.models_root)
    chosen = next((m for m in models if m.display_name == key), None) if key else (models[0] if models else None)
    if chosen is None:
        emit("ERROR", {
            "kind": "server",
            "message": "No startable llama.cpp vision model was found. Download one first.",
        })
        return 1

    manager = LlamaCppServerManager()
    manager.start(chosen, settings.llamacpp_url)
    emit("SERVER", {
        "running": is_server_healthy(settings.llamacpp_url),
        "model": chosen.display_name,
        "message": f"Started llama-server with {chosen.display_name}.",
    })
    return 0


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
        settings = load_settings(raw)
        if args.command == "preflight":
            return cmd_preflight(settings)
        if args.command == "models":
            return cmd_models(settings)
        if args.command == "setup-status":
            return cmd_setup_status(settings)
        if args.command == "install":
            return cmd_install(settings, args.key, args.backend)
        return cmd_start_server(settings, args.key)
    except Exception as exc:  # a traceback must never reach the UI
        emit("ERROR", {"kind": "internal", "message": f"{exc.__class__.__name__}: {exc}"})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
