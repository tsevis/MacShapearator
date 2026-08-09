# MacShapearator

Native macOS front-end for [Shapearator](https://github.com/tsevis/shapearator).

## Architecture

MacShapearator is a SwiftUI application that drives the Shapearator extraction
engine. The engine stays in Python — it is bundled into the app, pinned to a
released version, and never something the user installs. Communication is a
line-based protocol over stdout:

```
SwiftUI  ──spawns──▶  Scripts/extract_bridge.py  ──▶  services.extractor
         ──spawns──▶  Scripts/engine_bridge.py   ──▶  services.vision / model_registry
   ▲                                                  services.first_run / llamacpp_*
   └──  PREFLIGHT / PROGRESS / RESULT / MODELS / SETUP / INSTALLED / ERROR  ──┘
```

Model discovery, backend readiness, and model installation are all delegated to
the engine rather than reimplemented in Swift — which is why both the Ollama and
llama.cpp backends work, and why engine improvements need no Swift change.

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

## Distribution

```bash
./build_app.sh      # assemble the app
./release.sh        # sign, notarize, and build a .dmg
```

`release.sh` needs an Apple Developer account. It never handles credentials
directly: signing uses a `Developer ID Application` identity already in your
keychain, and notarization uses a `notarytool` keychain profile you create once:

```bash
xcrun notarytool store-credentials MacShapearator --apple-id you@example.com --team-id TEAMID
```

Run with `SKIP_NOTARIZE=1` to sign and package without submitting to Apple.
Publish the disk image as a release asset — never commit it.

### What gets bundled

`build_app.sh` copies the interpreter core *without* its site-packages and then
installs only the engine's five requirements. Rsyncing a development
interpreter wholesale is how the bundle once reached 4.5 GB, carrying
TensorFlow, PyTorch and JAX that Shapearator never imports.

It also refuses to bundle a Conda prefix or the Xcode system Python, neither of
which can be relocated into an app; set `PYTHON_SRC` to a pyenv version or a
python.org framework build if discovery picks nothing.

Inkscape's tutorials, translations and examples are stripped, since it is used
headlessly for `--query-all` and PNG export. That invalidates Inkscape's own
signature, so `release.sh` re-signs every nested binary inside-out.

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
