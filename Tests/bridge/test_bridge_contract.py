"""The bridge protocol, checked against the live engine.

Swift decodes every line these scripts print. `BridgeProtocolTests` pins what
we believe they emit and `FixtureContractTests` pins what they emitted once,
captured -- but a frozen capture cannot notice the day the engine renames a
field. A renamed key arrives in Swift as a nil optional and the app quietly
shows less than it used to.

So these run the real bridges against the real engine and assert that every
record still carries the keys `Models.swift` reads. Nothing here is mocked;
when one of these fails, the contract actually moved.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
SCRIPTS = REPO / "Scripts"

# Copied from Models.swift. A field that disappears here decodes to nil there.
PROGRESS_KEYS = {"phase", "current", "total", "message"}
PREFLIGHT_KEYS = {"ok", "provider", "message", "model", "visionCapable"}
ERROR_KEYS = {"kind", "message"}
RESULT_KEYS = {
    "inputPath", "outputDir", "providerSummary", "icons",
    "engineVersion", "naming", "commit", "warnings",
}
ICON_KEYS = {
    "index", "stem", "outputs", "previewPath", "canvasSize", "sourceSize",
    "sourceBounds", "metadataPath", "namingStatus", "namingError",
    "semanticTags", "semanticConfidence",
}
NAMING_KEYS = {"requested", "provider", "model", "named", "failed", "errors", "summary"}
COMMIT_KEYS = {"written", "replaced", "preserved"}
BACKEND_KEYS = {"ollamaReachable", "llamacppBinary"}
MODELS_KEYS = {"backends", "ollama", "llamacpp", "llamacppStartable", "directory"}
DESCRIPTOR_KEYS = {"name", "source", "location", "priority", "recommendation", "supportsVision"}
STARTABLE_KEYS = {"displayName", "priority", "source"}
SETUP_KEYS = {"backends", "setupMarked", "needsFirstRun", "candidates"}
CANDIDATE_KEYS = {
    "key", "displayName", "recommendation", "backend",
    "installed", "approxGB", "defaultSelected", "label",
}

BASE_SETTINGS = {
    "backendRoot": "", "pythonPath": "", "provider": "geometry",
    "ollamaURL": "http://127.0.0.1:11434", "ollamaModel": "",
    "llamacppURL": "http://127.0.0.1:8080", "llamacppModel": "",
    "modelsRoot": "", "localModelRoot": "", "localModelName": "",
    "semanticNaming": False, "defaultFormats": ["png"],
    "outputWidth": 512, "outputHeight": 512,
    "canvasMode": "uniform_to_largest",
    "bitmapExportMode": "transparent_preserve_interior",
    "padding": 12, "minArea": 200, "mergeGap": 13, "svgSplit": "auto",
    "lastInputPath": "", "lastOutputDir": "",
}


def engine_root() -> Path:
    """Where the Shapearator checkout is. Required -- a run without it tests
    nothing, so it fails loudly rather than skipping into a green tick."""
    for candidate in (os.environ.get("SHAPEARATOR_SRC"), REPO / "engine", REPO.parent / "shapearator"):
        if not candidate:
            continue
        path = Path(candidate)
        if (path / "services" / "extractor.py").exists():
            return path
    raise AssertionError(
        "No Shapearator checkout found. Set SHAPEARATOR_SRC to one; these tests "
        "exercise the real engine and cannot run without it."
    )


def settings_file(tmp_path: Path, **overrides) -> Path:
    payload = dict(BASE_SETTINGS, **overrides)
    path = tmp_path / "settings.json"
    path.write_text(json.dumps(payload))
    return path


def run_bridge(script: str, arguments: list[str]) -> tuple[list[tuple[str, dict]], int]:
    """Run a bridge script and parse its tagged lines, as Swift does."""
    completed = subprocess.run(
        [sys.executable, str(SCRIPTS / script), *arguments],
        cwd=engine_root(), capture_output=True, text=True, timeout=600,
    )
    events = [
        (tag, json.loads(body))
        for tag, _, body in (line.partition("\t") for line in completed.stdout.splitlines())
        if body
    ]
    return events, completed.returncode


def tagged(events: list[tuple[str, dict]], tag: str) -> list[dict]:
    return [body for name, body in events if name == tag]


def missing(required: set[str], record: dict) -> set[str]:
    return required - set(record)


@pytest.fixture(scope="module")
def extraction(tmp_path_factory) -> list[tuple[str, dict]]:
    """One real extraction of the engine's sample sheet, shared by the tests
    that read it -- it takes a few seconds and nothing mutates it."""
    tmp_path = tmp_path_factory.mktemp("extraction")
    events, code = run_bridge("extract_bridge.py", [
        "--settings", str(settings_file(tmp_path)),
        "--input", str(engine_root() / "docs" / "base.png"),
        "--output", str(tmp_path / "out"),
        "--preview-dir", str(tmp_path / "previews"),
        "--formats", "png",
    ])
    assert code == 0, f"the bridge failed: {events[-3:]}"
    return events


def test_no_setting_the_app_sent_was_rejected(extraction):
    """The bridge reports a rejected setting and carries on with the default.

    Every message here is a preference the user changed and the engine then
    ignored -- a key the alias table forgot, or one renamed on the engine side.
    It is silent from the app's side, which is the worst way for a setting to
    fail.
    """
    rejected = [
        record["message"]
        for record in tagged(extraction, "PROGRESS")
        if record["phase"] == "settings"
    ]
    assert rejected == [], f"the engine ignored settings the app sent: {rejected}"


# --- a folder of sheets, through the same bridge ---------------------------

@pytest.fixture(scope="module")
def folder_extraction(tmp_path_factory) -> list[tuple[str, dict]]:
    """One real run over a folder holding two sheets and one unreadable file."""
    tmp_path = tmp_path_factory.mktemp("folder")
    sheets = tmp_path / "sheets"
    sheets.mkdir()
    sample = engine_root() / "docs" / "base.png"
    (sheets / "first.png").write_bytes(sample.read_bytes())
    (sheets / "second.png").write_bytes(sample.read_bytes())
    (sheets / "broken.png").write_bytes(b"not a png")
    (sheets / "notes.txt").write_text("ignored")
    events, code = run_bridge("extract_bridge.py", [
        "--settings", str(settings_file(tmp_path)),
        "--input", str(sheets),
        "--output", str(tmp_path / "out"),
        "--preview-dir", str(tmp_path / "previews"),
        "--formats", "png",
    ])
    assert code == 0, f"the bridge failed: {events[-3:]}"
    return events


def test_a_folder_run_reports_one_result_the_app_can_decode(folder_extraction):
    results = tagged(folder_extraction, "RESULT")
    assert len(results) == 1, f"expected exactly one RESULT, got {len(results)}"
    result = results[0]
    assert not missing(RESULT_KEYS, result)
    assert not missing(NAMING_KEYS, result["naming"])
    assert not missing(COMMIT_KEYS, result["commit"])
    for icon in result["icons"]:
        assert not missing(ICON_KEYS, icon)


def test_a_folder_run_returns_every_sheet_s_icons(folder_extraction):
    """One RESULT, but the icons of both readable sheets are in it."""
    result = tagged(folder_extraction, "RESULT")[0]
    directories = {Path(icon["outputs"]["png"]).parent.parent.name for icon in result["icons"]}
    assert directories == {"first", "second"}


def test_an_unreadable_sheet_is_named_in_the_warnings(folder_extraction):
    result = tagged(folder_extraction, "RESULT")[0]
    assert any("broken.png" in warning for warning in result["warnings"]), result["warnings"]


def test_a_folder_run_still_reports_progress(folder_extraction):
    sheets = [p for p in tagged(folder_extraction, "PROGRESS") if p["phase"] == "sheet"]
    assert [(p["current"], p["total"]) for p in sheets] == [(1, 3), (2, 3), (3, 3)]


def test_a_folder_where_nothing_could_be_read_reports_an_error_not_a_result(tmp_path):
    """RESULT and a non-zero exit must never arrive together.

    Swift drains the events, sets .success on RESULT, then checks the exit
    code -- and a non-zero one overwrites that success with a bare
    "Extraction failed with status 1", burying the per-sheet reasons the
    warnings card is showing directly underneath it.
    """
    sheets = tmp_path / "sheets"
    sheets.mkdir()
    for name in ("one.png", "two.png"):
        (sheets / name).write_bytes(b"not a png")
    events, code = run_bridge("extract_bridge.py", [
        "--settings", str(settings_file(tmp_path)),
        "--input", str(sheets),
        "--output", str(tmp_path / "out"),
        "--preview-dir", str(tmp_path / "previews"),
        "--formats", "png",
    ])

    assert tagged(events, "RESULT") == [], "a run that extracted nothing is not a result"
    errors = tagged(events, "ERROR")
    assert len(errors) == 1, events
    assert "one.png" in errors[0]["message"] and "two.png" in errors[0]["message"]
    assert code == 1


def test_progress_carries_the_fields_the_progress_bar_reads(extraction):
    events = tagged(extraction, "PROGRESS")
    assert events, "no PROGRESS lines: the UI would sit at zero for the whole run"
    for record in events:
        assert not missing(PROGRESS_KEYS, record), record


def test_the_result_carries_every_field_the_app_decodes(extraction):
    results = tagged(extraction, "RESULT")
    assert len(results) == 1, f"expected exactly one RESULT, got {len(results)}"
    result = results[0]
    assert not missing(RESULT_KEYS, result)
    assert not missing(NAMING_KEYS, result["naming"])
    assert not missing(COMMIT_KEYS, result["commit"])
    assert isinstance(result["warnings"], list)


def test_every_icon_carries_its_naming_outcome(extraction):
    icons = tagged(extraction, "RESULT")[0]["icons"]
    assert icons, "the sample sheet has icons in it"
    for icon in icons:
        assert not missing(ICON_KEYS, icon), icon
        # ResultsPane branches on this; an unknown spelling shows nothing.
        assert icon["namingStatus"] in {"named", "failed", "not_requested"}


def test_an_unreachable_vision_backend_is_reported_as_recoverable(tmp_path):
    """Port 9 is the discard port: nothing answers, anywhere, including CI.
    This is the path behind the app's "export with generic names" prompt.

    A model name is set deliberately. Without one the engine decides naming
    was never requested and exports generic names in silence -- see
    test_naming_without_a_model_is_silently_not_requested.
    """
    events, code = run_bridge("extract_bridge.py", [
        "--settings", str(settings_file(
            tmp_path, provider="ollama", semanticNaming=True,
            ollamaModel="qwen2.5vl:3b", ollamaURL="http://127.0.0.1:9")),
        "--input", str(engine_root() / "docs" / "base.png"),
        "--output", str(tmp_path / "out"),
        "--formats", "png",
    ])
    assert code != 0

    preflight = tagged(events, "PREFLIGHT")
    assert preflight, "the app shows this message before anything else happens"
    assert not missing(PREFLIGHT_KEYS, preflight[0])
    assert preflight[0]["ok"] is False

    errors = tagged(events, "ERROR")
    assert errors, "a failed preflight must arrive as a structured ERROR"
    assert not missing(ERROR_KEYS, errors[0])
    # Without this flag the app offers no way past an absent model.
    assert errors[0].get("recoverable") is True


def test_a_fatal_error_arrives_as_a_structured_line_not_a_traceback(tmp_path):
    sheet = tmp_path / "sheet.gif"
    sheet.write_bytes(b"")
    events, code = run_bridge("extract_bridge.py", [
        "--settings", str(settings_file(tmp_path)),
        "--input", str(sheet),
        "--output", str(tmp_path / "out"),
        "--formats", "png",
    ])
    assert code != 0
    errors = tagged(events, "ERROR")
    assert errors, "the app would show 'Extraction failed.' and no reason"
    assert not missing(ERROR_KEYS, errors[0])
    assert errors[0].get("recoverable") is not True


def test_model_discovery_describes_both_backends(tmp_path):
    events, code = run_bridge("engine_bridge.py", ["--settings", str(settings_file(tmp_path)), "models"])
    assert code == 0
    records = tagged(events, "MODELS")
    assert records, "the Settings model picker has nothing to show without this"
    record = records[0]
    assert not missing(MODELS_KEYS, record)
    assert not missing(BACKEND_KEYS, record["backends"])
    # Whatever this machine happens to have installed, the shape is fixed.
    for descriptor in record["ollama"] + record["llamacpp"] + record["directory"]:
        assert not missing(DESCRIPTOR_KEYS, descriptor), descriptor
    for startable in record["llamacppStartable"]:
        assert not missing(STARTABLE_KEYS, startable), startable


def test_first_run_setup_offers_downloadable_models(tmp_path):
    events, code = run_bridge("engine_bridge.py", ["--settings", str(settings_file(tmp_path)), "setup-status"])
    assert code == 0
    records = tagged(events, "SETUP")
    assert records
    record = records[0]
    assert not missing(SETUP_KEYS, record)
    assert not missing(BACKEND_KEYS, record["backends"])
    # A machine with no Ollama and no llama-server -- CI, and a user's Mac
    # before first run -- correctly has nothing to offer, and the app says so.
    # The invariant that holds everywhere is the other direction.
    if record["backends"]["ollamaReachable"] or record["backends"]["llamacppBinary"]:
        assert record["candidates"], "a reachable backend must offer something to download"
    for candidate in record["candidates"]:
        assert not missing(CANDIDATE_KEYS, candidate), candidate


def test_preflight_answers_for_a_provider_that_needs_no_model(tmp_path):
    events, code = run_bridge("engine_bridge.py", ["--settings", str(settings_file(tmp_path)), "preflight"])
    assert code == 0
    records = tagged(events, "PREFLIGHT")
    assert records
    assert not missing(PREFLIGHT_KEYS, records[0])
    assert records[0]["ok"] is True


def test_naming_without_a_model_is_silently_not_requested(tmp_path):
    """Found while writing these: semantic naming on, a provider that needs a
    model, and no model chosen. The engine does not fail and does not warn --
    it reports `requested: false` and exports icon_001. The app must catch
    this before the run; `ExtractionPreconditions` is the guard, and this
    pins the engine behaviour the guard exists for."""
    events, code = run_bridge("extract_bridge.py", [
        "--settings", str(settings_file(
            tmp_path, provider="ollama", semanticNaming=True, ollamaModel="")),
        "--input", str(engine_root() / "docs" / "base.png"),
        "--output", str(tmp_path / "out"),
        "--formats", "png",
    ])
    assert code == 0
    result = tagged(events, "RESULT")[0]
    assert result["naming"]["requested"] is False
    assert not tagged(events, "ERROR")
    assert result["warnings"] == []
