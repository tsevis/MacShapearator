#!/usr/bin/env python3
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
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    raw = json.loads(args.settings.read_text(encoding="utf-8"))

    backend_root = Path(raw["backendRoot"]).resolve()
    if str(backend_root) not in sys.path:
        sys.path.insert(0, str(backend_root))

    from services.config_store import AppSettings
    from services.extractor import IconExtractor, ExtractionProgress, export_svg_to_png

    settings = AppSettings(
        provider=raw.get("provider", "geometry"),
        ollama_url=raw.get("ollamaURL", "http://127.0.0.1:11434"),
        ollama_model=raw.get("ollamaModel", "qwen2.5vl:3b"),
        local_model_root=raw.get("localModelRoot", ""),
        local_model_name=raw.get("localModelName", ""),
        semantic_naming=raw.get("semanticNaming", False),
        default_formats=list(raw.get("defaultFormats", ["png", "svg"])),
        output_width=int(raw.get("outputWidth", 512)),
        output_height=int(raw.get("outputHeight", 512)),
        canvas_mode=raw.get("canvasMode", "uniform_to_largest"),
        bitmap_export_mode=raw.get("bitmapExportMode", "transparent_preserve_interior"),
        padding=int(raw.get("padding", 12)),
        min_area=int(raw.get("minArea", 200)),
        merge_gap=int(raw.get("mergeGap", 13)),
        last_input_path=str(args.input),
        last_output_dir=str(args.output),
    )

    def on_progress(progress: ExtractionProgress) -> None:
        payload = {
            "phase": progress.phase,
            "current": progress.current,
            "total": progress.total,
            "message": progress.message,
        }
        print("PROGRESS\t" + json.dumps(payload, ensure_ascii=True), flush=True)

    result = IconExtractor(settings).extract(args.input.resolve(), args.output.resolve(), set(args.formats), progress_callback=on_progress)

    icons = []
    for icon in result.icons:
        preview_path = str(icon.preview_path) if icon.preview_path else None
        if preview_path is None and "svg" in icon.outputs:
            preview_dir = args.output / ".swift_previews"
            preview_dir.mkdir(parents=True, exist_ok=True)
            generated_preview = preview_dir / f"{icon.stem}.png"
            try:
                export_svg_to_png(icon.outputs["svg"], generated_preview)
                preview_path = str(generated_preview)
            except Exception:
                preview_path = None
        icons.append(
            {
                "index": icon.index,
                "stem": icon.stem,
                "outputs": {fmt: str(path) for fmt, path in icon.outputs.items()},
                "previewPath": preview_path,
                "canvasSize": list(icon.canvas_size),
                "sourceSize": list(icon.source_size),
                "sourceBounds": list(icon.source_bounds),
                "metadataPath": str(icon.metadata_path) if icon.metadata_path else None,
            }
        )

    payload = {
        "inputPath": str(result.input_path),
        "outputDir": str(result.output_dir),
        "providerSummary": result.provider_summary,
        "icons": icons,
    }
    print("RESULT\t" + json.dumps(payload, ensure_ascii=True), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
