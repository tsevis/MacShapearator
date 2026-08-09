# MacShapearator

Native macOS front-end for [Shapearator](https://github.com/tsevis/shapearator).

## Architecture

MacShapearator is a SwiftUI application that drives the Shapearator extraction
engine. The engine stays in Python — it is bundled into the app, pinned to a
released version, and never something the user installs. Communication is a
line-based protocol over stdout:

```
SwiftUI  ──spawns──▶  Scripts/extract_bridge.py  ──imports──▶  services.extractor
   ▲                                                                  │
   └────────  PREFLIGHT / PROGRESS / RESULT / ERROR lines  ◀───────────┘
```

See [PORTING_PLAN.md](PORTING_PLAN.md) for the roadmap to full parity.

## Requirements

- macOS 13 or newer
- Xcode 15 or newer
- For packaging: [XcodeGen](https://github.com/yonaskolb/XcodeGen), Inkscape,
  potrace (`brew install xcodegen potrace inkscape`)

## Run from source

Requires a Shapearator checkout. By default a sibling directory is used:

```bash
git clone https://github.com/tsevis/shapearator ../shapearator
./run.sh
```

Point elsewhere with `SHAPEARATOR_SRC=/path/to/shapearator ./run.sh`.

## Build a standalone app

```bash
./build_app.sh
```

This bundles the engine, a Python interpreter, Inkscape, and potrace into
`build/Build/Products/Debug/MacShapearator.app`.

Every external location is discovered automatically and can be overridden:

| Variable | Purpose | Default |
| --- | --- | --- |
| `SHAPEARATOR_SRC` | Shapearator checkout to bundle from | `../shapearator` |
| `SHAPEARATOR_REF` | Engine git ref to ship | the minimum supported version |
| `PYTHON_SRC` | Interpreter root to bundle | `sys.prefix` of `python3` on PATH |
| `INKSCAPE_APP` | Inkscape to bundle | `/Applications/Inkscape.app` |
| `POTRACE_PREFIX` | potrace install prefix | `brew --prefix potrace` |

## Engine versioning

The bundled engine is a build artifact, never a checked-in copy — `build_app.sh`
exports it from a git ref and stamps `Resources/BundledBackend/ENGINE_VERSION`.
At launch the app compares that against `AppRuntime.minimumEngineVersion` and
refuses to run against an older engine, so a stale bundle fails loudly instead
of silently extracting with out-of-date behaviour.

To ship a newer engine, tag it in the Shapearator repo and run:

```bash
SHAPEARATOR_REF=v0.4.2 ./build_app.sh
```
