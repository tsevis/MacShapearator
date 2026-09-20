"""Starting llama-server for a model the app downloaded.

The Settings pane offers a "Start Server" button beside every downloaded
llama.cpp model. Pressing it reported:

    ERROR {"kind": "internal", "message":
           "AttributeError: 'StartableLlamaModel' object has no attribute 'gguf_path'"}

The catalogue entry is not the file pair. A downloaded model carries `files`
(weights plus projector) and a cached one carries `hf_ref`; the server manager
has a separate entry point for each, and the bridge was handing it neither.
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from unittest.mock import MagicMock

import pytest

from test_bridge_contract import engine_root

BRIDGE = Path(__file__).resolve().parents[2] / "Scripts" / "engine_bridge.py"


@pytest.fixture(scope="module")
def bridge():
    sys.path.insert(0, str(engine_root()))
    spec = importlib.util.spec_from_file_location("engine_bridge_under_test", BRIDGE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def settings(tmp_path):
    from services.config_store import AppSettings

    return AppSettings(llamacpp_url="http://127.0.0.1:8080", models_root=str(tmp_path))


def _downloaded_model(tmp_path):
    from services.llamacpp_models import StartableLlamaModel
    from services.model_bootstrap import LlamaCppModelFiles

    files = LlamaCppModelFiles(gguf_path=tmp_path / "w.gguf", mmproj_path=tmp_path / "p.gguf")
    return StartableLlamaModel(display_name="Qwen3-VL", priority=10, source="downloaded", files=files)


def _cached_model():
    from services.llamacpp_models import StartableLlamaModel

    return StartableLlamaModel(display_name="Qwen3-VL", priority=10, source="cache",
                               hf_ref="Qwen/Qwen3-VL-GGUF:Q4_K_M")


def _run(bridge, monkeypatch, settings, model):
    manager = MagicMock()
    monkeypatch.setattr("services.llamacpp_models.available_startable_models", lambda _root: [model])
    monkeypatch.setattr("services.llamacpp_server.LlamaCppServerManager", lambda: manager)
    monkeypatch.setattr("services.llamacpp_server.is_server_healthy", lambda _url: False)
    bridge.cmd_start_server(settings, "Qwen3-VL")
    return manager


def test_a_downloaded_model_is_started_from_its_files(bridge, monkeypatch, settings, tmp_path):
    from services.model_bootstrap import LlamaCppModelFiles

    manager = _run(bridge, monkeypatch, settings, _downloaded_model(tmp_path))

    manager.start.assert_called_once()
    handed_over = manager.start.call_args.args[0]
    assert isinstance(handed_over, LlamaCppModelFiles), f"got {type(handed_over).__name__}"


def test_a_cached_model_is_started_from_its_hugging_face_ref(bridge, monkeypatch, settings):
    manager = _run(bridge, monkeypatch, settings, _cached_model())

    manager.start_hf.assert_called_once()
    assert manager.start_hf.call_args.args[0] == "Qwen/Qwen3-VL-GGUF:Q4_K_M"
    manager.start.assert_not_called()


def test_a_server_that_did_not_come_up_is_not_reported_as_started(bridge, monkeypatch, settings, tmp_path, capsys):
    """The first run of this printed
    SERVER {"running": false, ... "message": "Started llama-server with Qwen3-VL."}
    -- a success message carrying its own contradiction. The app shows the
    message, so the user is told it started while it did not."""
    _run(bridge, monkeypatch, settings, _downloaded_model(tmp_path))

    emitted = capsys.readouterr().out
    assert "ERROR" in emitted, emitted
    assert "Started llama-server" not in emitted, emitted


def test_the_server_outlives_the_bridge_process(bridge, monkeypatch, settings, tmp_path):
    """The engine registers an atexit hook that stops the server, so a server
    is never orphaned by the Tk GUI that owns it for its whole run.

    This app is not that. Every bridge command is its own short-lived process,
    so the hook fires microseconds after the server is reported as started:
    `SERVER {"running": true}` and then nothing listening. A server the user
    started from Settings has to outlive the command that started it, so the
    hook is dropped once the server is up and healthy.
    """
    unregistered = []
    monkeypatch.setattr("atexit.unregister", unregistered.append)

    # Not serving before the launch, serving after it -- as in a real run.
    probes = {"n": 0}

    def healthy(_url):
        probes["n"] += 1
        return probes["n"] > 1

    monkeypatch.setattr("services.llamacpp_server.is_server_healthy", healthy)
    manager = MagicMock()
    monkeypatch.setattr("services.llamacpp_models.available_startable_models",
                        lambda _root: [_downloaded_model(tmp_path)])
    monkeypatch.setattr("services.llamacpp_server.LlamaCppServerManager", lambda: manager)

    bridge.cmd_start_server(settings, "Qwen3-VL")

    assert manager.stop in unregistered, "the atexit hook still kills the server on exit"
