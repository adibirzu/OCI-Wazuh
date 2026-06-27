import json
from pathlib import Path

from m11.orchestrator import RunController, StageResult


STAGES = ("preflight", "reconcile", "apply", "validate", "teardown")


def test_full_controller_uses_fresh_run_and_executes_ordered_stages(tmp_path: Path) -> None:
    (tmp_path / "stale.json").write_text("{}", encoding="utf-8")
    called: list[str] = []

    def execute(stage: str, run_id: str) -> StageResult:
        called.append(stage)
        return StageResult(stage=stage, state="green", details={"run_id": run_id})

    summary = RunController(tmp_path, execute).run(mode="orm", run_id="run-current")

    assert called == list(STAGES)
    assert not (tmp_path / "stale.json").exists()
    assert summary.state == "green"
    assert summary.run_id == "run-current"
    assert json.loads((tmp_path / "terminal.json").read_text(encoding="utf-8"))["state"] == "green"


def test_controller_blocks_mutating_stages_after_failed_preflight(tmp_path: Path) -> None:
    called: list[str] = []

    def execute(stage: str, run_id: str) -> StageResult:
        called.append(stage)
        state = "failed" if stage == "preflight" else "green"
        return StageResult(stage=stage, state=state, details={})

    summary = RunController(tmp_path, execute).run(mode="local", run_id="run-blocked")

    assert called == ["preflight"]
    assert summary.state == "failed"
    assert summary.completed_stages == ("preflight",)


def test_stop_after_is_incomplete_and_never_release_green(tmp_path: Path) -> None:
    summary = RunController(
        tmp_path,
        lambda stage, run_id: StageResult(stage=stage, state="green", details={}),
    ).run(mode="local", run_id="run-debug", stop_after="reconcile")

    assert summary.state == "stopped"
    assert summary.completed_stages == ("preflight", "reconcile")
