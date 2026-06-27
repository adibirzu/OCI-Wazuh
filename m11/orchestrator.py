"""Unified, testable M11 stage controller."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Mapping

from m11.artifacts import begin_run, utc_timestamp, write_gate


STAGES = ("preflight", "reconcile", "apply", "validate", "teardown")


@dataclass(frozen=True)
class StageResult:
    stage: str
    state: str
    details: Mapping[str, Any]

    def __post_init__(self) -> None:
        if self.state not in {"green", "failed", "skipped"}:
            raise ValueError("stage state must be green, failed, or skipped")


@dataclass(frozen=True)
class RunSummary:
    run_id: str
    mode: str
    state: str
    completed_stages: tuple[str, ...]


Executor = Callable[[str, str], StageResult]


class RunController:
    def __init__(self, artifact_directory: Path, executor: Executor) -> None:
        self._artifact_directory = Path(artifact_directory)
        self._executor = executor

    def _write_terminal(self, summary: RunSummary) -> None:
        payload = {
            "completed_stages": list(summary.completed_stages),
            "mode": summary.mode,
            "run_id": summary.run_id,
            "state": summary.state,
            "timestamp": utc_timestamp(),
        }
        (self._artifact_directory / "terminal.json").write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    def run(
        self,
        mode: str,
        run_id: str | None = None,
        stop_after: str | None = None,
    ) -> RunSummary:
        if stop_after is not None and stop_after not in STAGES:
            raise ValueError(f"stop_after must be one of: {', '.join(STAGES)}")
        context = begin_run(self._artifact_directory, mode=mode, run_id=run_id)
        completed: list[str] = []
        terminal_state = "green"
        for stage in STAGES:
            try:
                result = self._executor(stage, context["run_id"])
                if result.stage != stage:
                    raise ValueError(f"executor returned {result.stage!r} for {stage!r}")
            except Exception as exc:  # runner boundary: normalize errors into redacted stage state
                result = StageResult(stage, "failed", {"error_type": type(exc).__name__})
            write_gate(self._artifact_directory, context, stage, result.state, result.details)
            completed.append(stage)
            if result.state == "failed":
                terminal_state = "failed"
                break
            if stage == stop_after:
                terminal_state = "stopped"
                break
        summary = RunSummary(context["run_id"], mode, terminal_state, tuple(completed))
        self._write_terminal(summary)
        return summary
