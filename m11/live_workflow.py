"""Integration of reconciliation decisions with the unified stage controller."""

from __future__ import annotations

import json
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from m11.destroy_guard import wait_for_zero_residuals
from m11.orchestrator import RunController, RunSummary, StageResult
from m11.reconciliation import (
    ConnectorCapacity,
    ExpectedResource,
    ObservedResource,
    ReconciliationDecision,
    decide_connector_capacity,
    reconcile_resources,
)


@dataclass(frozen=True)
class PreflightSnapshot:
    project_name: str
    expected: tuple[ExpectedResource, ...]
    observed: tuple[ObservedResource, ...]
    connector_capacity: ConnectorCapacity


class LiveBackend(Protocol):
    def preflight(self, run_id: str) -> PreflightSnapshot: ...

    def import_resource(self, address: str, resource_id: str) -> None: ...

    def apply(self, run_id: str) -> None: ...

    def validate(self, run_id: str) -> bool: ...

    def cleanup_reused_hosts(self, run_id: str) -> bool: ...

    def destroy(self, run_id: str) -> None: ...

    def residual_resource_ids(self) -> list[str]: ...


class LiveWorkflow:
    def __init__(
        self,
        artifact_directory: Path,
        backend: LiveBackend,
        *,
        residual_attempts: int = 12,
        residual_interval: float = 10,
    ) -> None:
        self._artifact_directory = Path(artifact_directory)
        self._backend = backend
        self._residual_attempts = residual_attempts
        self._residual_interval = residual_interval
        self._snapshot: PreflightSnapshot | None = None

    def _decisions(self, snapshot: PreflightSnapshot) -> tuple[ReconciliationDecision, ...]:
        decisions: list[ReconciliationDecision] = []
        for expected in snapshot.expected:
            if expected.resource_type == "oci_sch_service_connector":
                decision = decide_connector_capacity(
                    expected,
                    snapshot.observed,
                    snapshot.connector_capacity,
                    snapshot.project_name,
                )
            else:
                decision = reconcile_resources(
                    [expected], snapshot.observed, snapshot.project_name
                ).decisions[0]
            decisions.append(decision)
        return tuple(decisions)

    def _write_reconciliation_report(
        self,
        run_id: str,
        decisions: tuple[ReconciliationDecision, ...],
    ) -> None:
        counts = dict(sorted(Counter(decision.action for decision in decisions).items()))
        blocked_decisions = tuple(
            decision for decision in decisions if decision.action not in {"create", "import"}
        )
        blocked = sorted(decision.reason for decision in blocked_decisions)
        blocked_details = sorted(
            (
                {
                    "action": decision.action,
                    "address": decision.address,
                    "reason": decision.reason,
                }
                for decision in blocked_decisions
            ),
            key=lambda item: item["address"],
        )
        payload = {
            "blocked": blocked_details,
            "blocked_reasons": blocked,
            "counts": counts,
            "operator_remediation": (
                "Review each blocked Terraform address, verify live ownership and configuration, "
                "then explicitly import, remove, or rename the conflicting resource before rerunning."
                if blocked_details
                else ""
            ),
            "run_id": run_id,
            "state": "failed" if blocked else "green",
        }
        (self._artifact_directory / "reconciliation-report.json").write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    def _execute(self, stage: str, run_id: str) -> StageResult:
        if stage == "preflight":
            self._snapshot = self._backend.preflight(run_id)
            return StageResult(stage, "green", {"project": self._snapshot.project_name})

        if self._snapshot is None:
            return StageResult(stage, "failed", {"reason": "missing_preflight_snapshot"})

        if stage == "reconcile":
            decisions = self._decisions(self._snapshot)
            self._write_reconciliation_report(run_id, decisions)
            blocked = tuple(
                decision for decision in decisions if decision.action not in {"create", "import"}
            )
            if blocked:
                return StageResult(
                    stage,
                    "failed",
                    {"blocked_count": len(blocked), "reason": blocked[0].reason},
                )
            for decision in decisions:
                if decision.action == "import" and decision.resource_id is not None:
                    self._backend.import_resource(decision.address, decision.resource_id)
            return StageResult(stage, "green", {"counts": len(decisions)})

        if stage == "apply":
            self._backend.apply(run_id)
            return StageResult(stage, "green", {})

        if stage == "validate":
            state = "green" if self._backend.validate(run_id) else "failed"
            return StageResult(stage, state, {})

        if stage == "teardown":
            if not self._backend.cleanup_reused_hosts(run_id):
                return StageResult(stage, "failed", {"reason": "reused_host_cleanup_failed"})
            self._backend.destroy(run_id)
            residual = wait_for_zero_residuals(
                self._backend.residual_resource_ids,
                attempts=self._residual_attempts,
                interval_seconds=self._residual_interval,
            )
            return StageResult(
                stage,
                "green" if residual["ok"] else "failed",
                {
                    "attempts": residual["attempts"],
                    "residual_count": residual["residual_count"],
                },
            )

        return StageResult(stage, "failed", {"reason": "unknown_stage"})

    def run(
        self,
        *,
        mode: str,
        run_id: str | None = None,
        stop_after: str | None = None,
    ) -> RunSummary:
        controller = RunController(self._artifact_directory, self._execute)
        return controller.run(mode=mode, run_id=run_id, stop_after=stop_after)
