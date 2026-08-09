# MacShapearator

Native macOS SwiftUI front-end for Shapearator.

## Current architecture

This first native version provides:
- a macOS-native SwiftUI workspace and settings UI
- persisted local settings in Application Support
- extraction execution through the local Python Shapearator engine
- native preview and results browsing

That means the app is usable immediately while the extraction core continues moving from Python into Swift over time.

## Run

```bash
./run.sh
```

## Build Standalone App

```bash
./build_app.sh
```

This generates:

```bash
/Users/tsevis/AI/ClaudeCode/MacShapearator/build/Build/Products/Debug/MacShapearator.app
```

## Notes

- Default backend root: `/Users/tsevis/AI/ClaudeCode/shapearator`
- Default Python runtime: `/Users/tsevis/.pyenv/versions/3.10.13/bin/python`
- The bridge script lives at `Scripts/extract_bridge.py`
- The standalone Xcode app bundles a local copy of the Python backend in `Resources/BundledBackend`
