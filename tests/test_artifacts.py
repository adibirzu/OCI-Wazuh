import json
from pathlib import Path

import pytest

from m11.artifacts import begin_run, write_gate


def test_begin_run_removes_stale_artifacts_and_records_context(tmp_path: Path) -> None:
    stale = tmp_path / "M2-bastion-connectivity.txt"
    stale.write_text("state=failed\n", encoding="utf-8")
    nested = tmp_path / "old" / "output.json"
    nested.parent.mkdir()
    nested.write_text("{}", encoding="utf-8")

    context = begin_run(tmp_path, mode="orm", run_id="run-123")

    assert not stale.exists()
    assert not nested.exists()
    assert context["run_id"] == "run-123"
    assert context["mode"] == "orm"
    assert context["state"] == "green"
    assert context["timestamp"].endswith("Z")
    assert json.loads((tmp_path / "_run.json").read_text(encoding="utf-8")) == context


@pytest.mark.parametrize("state", ["green", "failed", "skipped"])
def test_write_gate_uses_explicit_state_and_run_metadata(tmp_path: Path, state: str) -> None:
    context = begin_run(tmp_path, mode="existing-network", run_id="run-456")

    artifact = write_gate(tmp_path, context, "M11", state, {"windows_mode": "skip"})
    payload = json.loads(artifact.read_text(encoding="utf-8"))

    assert payload == {
        "gate": "M11",
        "mode": "existing-network",
        "run_id": "run-456",
        "state": state,
        "timestamp": context["timestamp"],
        "windows_mode": "skip",
    }


def test_write_gate_rejects_ambiguous_state(tmp_path: Path) -> None:
    context = begin_run(tmp_path, mode="local", run_id="run-789")

    with pytest.raises(ValueError, match="green, failed, or skipped"):
        write_gate(tmp_path, context, "M11", "red", {})
