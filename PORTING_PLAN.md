# MacShapearator — Plan to Reach Full Parity with Shapearator 0.4.1

Target: make MacShapearator the definitive way to run Shapearator on a Mac —
everything the Python app can do, presented natively, installable by someone who
has never heard of Python.

Source of truth for the engine: <https://github.com/tsevis/shapearator> (v0.4.1).

---

## 1. Where the project actually stands

MacShapearator is **not a reimplementation**. All 1,129 lines of Swift are UI and
process management; the extraction engine is the Python app, driven through
`Scripts/extract_bridge.py`:

```
SwiftUI  ──spawns──▶  python extract_bridge.py  ──imports──▶  services.extractor
   ▲                                                                │
   └──────────  PROGRESS\t{…} / RESULT\t{…} on stdout  ◀────────────┘
```

This is the single most important fact for planning: **the five audit fixes in
v0.4.1 are already MacShapearator's fixes**, the moment it points at the current
engine. Verified — running the existing bridge against v0.4.1 produces the new
pipeline unchanged:

```
PROGRESS {"phase": "commit", "message": "Publishing export"}
PROGRESS {"phase": "commit", "message": "Published 8 files"}
```

### Why we keep Python as the engine

A from-scratch Swift port would mean reimplementing OpenCV contour detection,
potrace tracing, Inkscape orchestration, SVG definition resolution, and two
vision-model clients. That is months of work to reproduce behaviour that is
already correct and covered by 270 tests, and it permanently forks the bug
surface into two codebases that drift apart. The README's ambition of "moving
the extraction core from Python into Swift over time" is the one strategic idea
this plan rejects — see §8 for the honest cost analysis.

The plan instead makes the Python engine an **invisible implementation detail**:
bundled, versioned, never mentioned in the UI, never something a user installs.

---

## 2. Gap analysis: Python 0.4.1 vs MacShapearator today

| Capability | Python 0.4.1 | Mac today | Phase |
| --- | --- | --- | --- |
| Geometry extraction, all formats | yes | yes (via bridge) | — |
| Detection presets | yes | yes | — |
| Staged, manifest-tracked exports | yes | inherited, not surfaced | 3 |
| Definition-preserving SVG | yes | inherited | — |
| Publishable metadata (no local paths) | yes | inherited | — |
| Semantic naming, Ollama | yes | yes | — |
| Semantic naming, SVG-only exports | yes | inherited | 3 |
| **llama.cpp backend** | yes | **absent entirely** | 2 |
| **Enforced preflight before export** | yes | **absent** (advisory, duplicated in Swift) | 1 |
| **`allow_unnamed` choice** | yes | **absent** | 1 |
| **Per-icon naming status / counts** | yes | **absent** | 3 |
| **Run warnings surfaced** | yes | **absent** | 3 |
| First-run model download | full flow | Ollama pull only | 2 |
| Model catalog / registry | yes | Ollama `list` parsing | 2 |
| Settings validation | schema-aware | none | 2 |
| Runs on a machine that isn't yours | yes | **no** (hardcoded paths) | 0 |

---

## 3. Known defects to fix

Each was confirmed by reading or running the code, not inferred.

1. **The shipped app runs a stale engine.** `Resources/BundledBackend/services/`
   contains 5 modules; v0.4.1 has 21. It is missing `svg_ops`, `semantic_naming`,
   `export_commit`, `settings_schema`, `metadata_paths`, `geometry`,
   `raster_ops`, `vision` and more — it predates even the llama.cpp work. It
   still imports cleanly, which is the trap: **the packaged .app silently runs
   the old engine with all five audit bugs.** `build_app.sh` never syncs it; the
   copy was made by hand.

2. **The bridge does not catch `SemanticPreflightError`.** An unreachable model
   now surfaces in the Swift error dialog as a raw Python traceback:
   ```
   services.semantic_naming.SemanticPreflightError: Ollama is not reachable at …
   ```

3. **The bridge never passes `allow_unnamed`**, so the "export with generic
   names instead" choice the engine offers is unreachable from the Mac app.

4. **The bridge discards the new result data.** `ExtractionResultRecord` carries
   only `inputPath`, `outputDir`, `providerSummary`, `icons`. Nothing conveys
   per-icon `naming_status` / `naming_error`, named/failed counts, run warnings,
   or the commit report's replaced-file count.

5. **Hardcoded personal paths in four places** — `Models.swift:4,5,9`,
   `AppRuntime.swift:138`, `build_app.sh:6`, and `README.md`. The app cannot run
   for anyone else, and the paths disclose an account name. This is the same
   class of leak fixed engine-side in v0.4.1.

6. **The bundle is ~7 GB.** `build_app.sh:14` rsyncs an entire pyenv, which on
   this machine includes TensorFlow, PyTorch, JAX, polars and llvmlite — none of
   which Shapearator uses. Its real dependencies are opencv-python, numpy,
   Pillow, requests and huggingface_hub.

7. **`.swift_previews/` is written permanently into the user's output folder.**
   `extract_bridge.py:64-72` renders UI thumbnails there. They are untracked by
   the run manifest, so nothing ever cleans them up.

8. **The bridge script is duplicated** byte-identically in `Scripts/` and
   `Resources/Scripts/`, synced by hand.

9. **Preflight logic is duplicated in Swift.** `OllamaRuntimeViewModel` re-implements
   reachability and model-presence checks that `services/vision.preflight()`
   already does — and only for Ollama, which is why llama.cpp is absent.

10. **The settings bridge is a hand-maintained mapping.** `extract_bridge.py:31-48`
    converts camelCase to snake_case field by field; any new engine setting is
    silently dropped.

---

## 4. Phase 0 — Foundation (½ day)

Make the project buildable by someone other than its author.

- [x] `git init`, `.gitignore` excluding the 4.5 GB interpreter, Inkscape.app,
      potrace, `.dmg`, and the vendored engine copy; publish to
      `github.com/tsevis/MacShapearator` (private).
- [ ] Remove every hardcoded `/Users/tsevis/…`. Replace with:
      - `backendRoot` — default empty, resolved to the bundled engine.
      - `pythonPath` — default empty, resolved to the bundled interpreter.
      - `localModelRoot` — default to `~/Library/Application Support/MacShapearator/models`.
      - `build_app.sh` — read `PYTHON_SRC`, `INKSCAPE_APP`, `POTRACE_PREFIX` from
        the environment with sensible discovery, not literals.
- [ ] De-duplicate the bridge: keep `Scripts/extract_bridge.py`, have
      `build_app.sh` copy it into `Resources/` at package time.
- [ ] Decide the fate of the 1.7 GB `MacShapearator.dmg` in the working tree
      (delete locally; publish future builds as GitHub release assets).

**Done when:** a fresh clone builds and runs on a Mac that has never seen this
project, with no path editing.

---

## 5. Phase 1 — Correctness parity (1 day)

Close the gap between what the app ships and what the engine does.

### 1a. Make the vendored engine a build artifact, not a copy

Add to `build_app.sh`, before `xcodegen generate`:

```zsh
ENGINE_SRC="${SHAPEARATOR_SRC:-../shapearator}"
ENGINE_REF="${SHAPEARATOR_REF:-v0.4.1}"
rm -rf Resources/BundledBackend
git -C "$ENGINE_SRC" archive "$ENGINE_REF" services shapearator.py \
  | tar -x -C Resources/BundledBackend
echo "$ENGINE_REF" > Resources/BundledBackend/ENGINE_VERSION
```

Pinning to a tag rather than a working tree makes the shipped engine
reproducible, and `ENGINE_VERSION` lets the app show which engine it carries.

Add a startup assertion: compare `ENGINE_VERSION` against a
`MINIMUM_ENGINE_VERSION` constant in Swift and refuse to run against an older
engine with a clear message. This defect class must not recur silently.

### 1b. Repair the bridge

- Catch `SemanticPreflightError` and emit a structured event rather than a
  traceback:
  ```
  PREFLIGHT\t{"ok": false, "message": "...", "provider": "ollama"}
  ```
- Accept `--allow-unnamed` and pass it to `extract()`.
- Emit the full result: per-icon `namingStatus` / `namingError`, plus
  `naming` (`requested`, `provider`, `model`, `named`, `failed`, `errors`),
  `warnings`, and `commit` (`written`, `replaced`, `preserved`).
- Move `.swift_previews` out of the user's output folder into
  `NSTemporaryDirectory()`, passed in by Swift and cleaned on exit.
- Replace the hand-written settings mapping with a generated one: have the
  bridge accept the settings JSON keyed by the engine's own field names and
  build `AppSettings` via `services.settings_schema.coerce_settings`, so the
  engine's validation is reused and new fields cannot be silently dropped.

**Done when:** an unreachable model produces the engine's actionable message in
a native dialog, and the packaged app's metadata reports `app_version 0.4.1`.

---

## 6. Phase 2 — Feature parity (2–3 days)

### 2a. llama.cpp backend

The engine has a full dual-backend; the Mac app knows only Ollama. Add:

- `llamacppURL` / `llamacppModel` to `ExtractionSettings` and the bridge.
- A provider picker offering Geometry / Ollama / llama.cpp.
- llama.cpp model discovery via the engine (`services/llamacpp_models.py`),
  not reimplemented in Swift.
- Optional server start, mirroring `services/llamacpp_server.py`.

### 2b. Retire the duplicated Swift preflight

Replace `OllamaRuntimeViewModel`'s bespoke checks with a bridge call that runs
`services.vision.preflight()` and returns a `PreflightResult`. One
implementation, both backends, and the Mac app inherits future engine work for
free. Keep the Swift-side niceties (install links, `ollama pull`) as actions
layered on top of the engine's verdict.

### 2c. First-run setup

Surface `services/first_run.py` and `services/model_bootstrap.py`: detect
available backends, offer the recommended vision model, download with real
progress. This is what makes the app installable by a non-technical user.

---

## 7. Phase 3 — Surface the engine's new state (1 day)

Mirror in SwiftUI what the Tk GUI and CLI already report:

- **Preflight prompt.** On Extract, if the backend is not ready, present the
  engine's message with *Export with generic names* / *Cancel* — the same choice
  `--allow-unnamed` gives the CLI.
- **Naming outcome.** "4 named via ollama/qwen2.5vl:3b", or "3 named, 1 failed"
  with per-icon status in the results list and the reason on the failed row.
- **Replacement report.** "94 files replaced from the previous run" and the
  first-run warning about untracked files left in place — this is a
  destructive-looking operation and the user should see what happened.
- **Warnings** in a non-modal banner rather than a blocking alert.

Extend `Models.swift` accordingly; every field already exists engine-side.

---

## 8. Phase 4 — Distribution (2–3 days)

This is what turns a working app into a shippable one.

- **Slim the interpreter.** Build a purpose-made venv from
  `requirements.txt` instead of rsyncing a personal pyenv. Expected ~7 GB → ~250–350 MB.
  Strip tests, `__pycache__`, and unused `site-packages`.
- **Slim Inkscape.** 626 MB is most of the remainder. Evaluate replacing it with
  `resvg` or `librsvg` (a few MB) for rasterisation; note that
  `services/svg_ops.query_svg_boxes` depends on `inkscape --query-all`, so this
  needs an engine-side abstraction — worth doing, and it also fixes the
  one-process-per-icon performance issue noted in the engine backlog.
- **Codesign and notarize**; the app spawns subprocesses and needs correct
  entitlements and a hardened runtime.
- **Ship the .dmg as a GitHub release asset**, never in the repository.

---

## 9. Phase 5 — Testing (ongoing, start in Phase 1)

The Swift side currently has no tests at all.

- **Bridge contract tests, in Python**, living in the engine repo: given a
  settings payload, assert the emitted `PROGRESS` / `RESULT` / `PREFLIGHT` lines.
  This is the interface most likely to break silently, and it is cheap to test.
- **Swift unit tests** for JSON decoding of every event, path resolution in
  `AppRuntime`, and settings round-tripping.
- **One end-to-end smoke test** in CI: build, run a bundled sample sheet
  headlessly, assert the icon count and that metadata reports the expected
  `app_version`.
- **Engine-version guard test** (Phase 1a) so a stale bundle fails loudly.

---

## 10. On rewriting the engine in Swift

Recorded so the question is settled rather than revisited.

| Component | Swift feasibility | Verdict |
| --- | --- | --- |
| Blob detection, masks | Vision / Core Image, plausible | Feasible |
| Canvas composition | Core Graphics, straightforward | Feasible |
| Bitmap → vector tracing | no potrace equivalent; would need porting or FFI | Hard |
| SVG parse / fragment / normalize | no comparable library; hand-rolled | Hard |
| Element bounds query | currently `inkscape --query-all`; needs a real SVG engine | Hard |
| Vision-model clients | trivial in Swift | Feasible |

The two "hard" rows are exactly where v0.4.1's correctness work landed
(definition resolution, fragment building). Reimplementing them means
re-deriving that correctness from scratch, without the 270 tests.

**Recommendation:** keep Python. If removing the runtime dependency becomes a
goal, the productive path is a smaller interpreter and a lighter SVG tool
(Phase 4), not a rewrite. Should a rewrite ever be justified, do it one
component at a time behind the existing bridge boundary, with the Python
implementation as the reference oracle.

---

## 11. Sequencing and effort

| Phase | Outcome | Est. |
| --- | --- | --- |
| 0 | Builds on any Mac; repo clean | ½ day |
| 1 | Ships the correct engine; no tracebacks in the UI | 1 day |
| 2 | llama.cpp, unified preflight, first-run setup | 2–3 days |
| 3 | New engine state visible natively | 1 day |
| 4 | ~300 MB signed, notarized, distributable app | 2–3 days |
| 5 | Contract + smoke tests | ongoing |

Phases 0–1 are the ones that matter most: until they land, the packaged app
ships known-buggy behaviour. Phases 2–3 are what make it a peer of the Python
app rather than a subset. Phase 4 is what makes it something you can hand to
someone.

## 12. Definition of done

MacShapearator is the ultimate port when:

1. A user downloads one signed `.dmg`, opens it, and extracts icons without
   installing Python, Inkscape, potrace, or Ollama.
2. Every Python 0.4.1 capability is reachable from the native UI, including
   llama.cpp and first-run model setup.
3. The engine is pinned, version-checked at startup, and cannot silently drift.
4. Preflight failures, partial naming, and export replacement are all surfaced
   in the UI as clearly as the CLI reports them.
5. Nothing in the repository or the exported artifacts names a local filesystem.
