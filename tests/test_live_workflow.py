import json
from dataclasses import dataclass, field
from pathlib import Path

from m11.live_workflow import LiveWorkflow, PreflightSnapshot
from m11.reconciliation import ConnectorCapacity, ExpectedResource, ObservedResource


PROJECT = "oci-wazuh-demo"


def connector_expected() -> ExpectedResource:
    return ExpectedResource(
        address="module.service_connector.oci_sch_service_connector.flow",
        resource_type="oci_sch_service_connector",
        name=f"{PROJECT}-flow",
        tags={"project": PROJECT},
        configuration={"source": "flow", "target": "stream"},
    )


def connector_observed(resource_id: str = "private-connector-id") -> ObservedResource:
    return ObservedResource(
        resource_id=resource_id,
        resource_type="oci_sch_service_connector",
        name=f"{PROJECT}-flow",
        lifecycle_state="ACTIVE",
        tags={"project": PROJECT},
        configuration={"source": "flow", "target": "stream"},
    )


@dataclass
class FakeBackend:
    snapshot: PreflightSnapshot
    validation_green: bool = True
    cleanup_green: bool = True
    residual_sequence: list[list[str]] = field(default_factory=lambda: [[]])
    calls: list[str] = field(default_factory=list)

    def preflight(self, run_id: str) -> PreflightSnapshot:
        self.calls.append("preflight")
        return self.snapshot

    def import_resource(self, address: str, resource_id: str) -> None:
        self.calls.append(f"import:{address}")

    def apply(self, run_id: str) -> None:
        self.calls.append("apply")

    def validate(self, run_id: str) -> bool:
        self.calls.append("validate")
        return self.validation_green

    def cleanup_reused_hosts(self, run_id: str) -> bool:
        self.calls.append("cleanup")
        return self.cleanup_green

    def destroy(self, run_id: str) -> None:
        self.calls.append("destroy")

    def residual_resource_ids(self) -> list[str]:
        self.calls.append("residuals")
        if len(self.residual_sequence) > 1:
            return self.residual_sequence.pop(0)
        return self.residual_sequence[0]


def snapshot(
    observed: tuple[ObservedResource, ...] = (),
    capacity: ConnectorCapacity = ConnectorCapacity(limit=2, active_count=0),
) -> PreflightSnapshot:
    return PreflightSnapshot(
        project_name=PROJECT,
        expected=(connector_expected(),),
        observed=observed,
        connector_capacity=capacity,
    )


def test_clean_deploy_runs_apply_validation_and_zero_residual_teardown(tmp_path: Path) -> None:
    backend = FakeBackend(snapshot())

    summary = LiveWorkflow(tmp_path, backend, residual_attempts=2, residual_interval=0).run(
        mode="orm", run_id="clean-run"
    )

    assert summary.state == "green"
    assert backend.calls == ["preflight", "apply", "validate", "cleanup", "destroy", "residuals"]
    report = json.loads((tmp_path / "reconciliation-report.json").read_text(encoding="utf-8"))
    assert report["counts"] == {"create": 1}


def test_partial_deploy_imports_exact_match_before_apply(tmp_path: Path) -> None:
    backend = FakeBackend(snapshot((connector_observed(),), ConnectorCapacity(limit=1, active_count=1)))

    summary = LiveWorkflow(tmp_path, backend, residual_attempts=1, residual_interval=0).run(
        mode="local", run_id="partial-run", stop_after="apply"
    )

    assert summary.state == "stopped"
    assert backend.calls[:3] == [
        "preflight",
        "import:module.service_connector.oci_sch_service_connector.flow",
        "apply",
    ]
    report_text = (tmp_path / "reconciliation-report.json").read_text(encoding="utf-8")
    assert "private-connector-id" not in report_text
    assert '"import": 1' in report_text


def test_exact_nonimportable_match_is_adopted_by_apply_without_import(tmp_path: Path) -> None:
    dashboard_type = "oci_management_dashboard_management_dashboards_import"
    dashboard_expected = ExpectedResource(
        address="oci_management_dashboard_management_dashboards_import.wazuh[0]",
        resource_type=dashboard_type,
        name=f"{PROJECT}-correlation",
        tags={"project": PROJECT},
        configuration={"fingerprint": "matching"},
    )
    dashboard_observed = ObservedResource(
        resource_id="private-dashboard-id",
        resource_type=dashboard_type,
        name=f"{PROJECT}-correlation",
        lifecycle_state="ACTIVE",
        tags={"project": PROJECT},
        configuration={"fingerprint": "matching"},
        importable=False,
    )
    backend = FakeBackend(
        PreflightSnapshot(
            project_name=PROJECT,
            expected=(dashboard_expected,),
            observed=(dashboard_observed,),
            connector_capacity=ConnectorCapacity(limit=1, active_count=0),
        )
    )

    summary = LiveWorkflow(tmp_path, backend).run(
        mode="orm", run_id="dashboard-run", stop_after="apply"
    )

    assert summary.state == "stopped"
    assert backend.calls == ["preflight", "apply"]
    report = json.loads((tmp_path / "reconciliation-report.json").read_text(encoding="utf-8"))
    assert report["counts"] == {"adopt_on_apply": 1}


def test_connector_quota_exhaustion_blocks_before_import_or_apply(tmp_path: Path) -> None:
    backend = FakeBackend(snapshot(capacity=ConnectorCapacity(limit=1, active_count=1)))

    summary = LiveWorkflow(tmp_path, backend).run(mode="orm", run_id="quota-run")

    assert summary.state == "failed"
    assert backend.calls == ["preflight"]
    report = json.loads((tmp_path / "reconciliation-report.json").read_text(encoding="utf-8"))
    assert report["blocked_reasons"] == ["service_connector_quota_exhausted"]


def test_blocked_report_is_actionable_without_resource_identifiers(tmp_path: Path) -> None:
    drifted = ObservedResource(
        resource_id="private-drifted-id",
        resource_type="oci_sch_service_connector",
        name=f"{PROJECT}-flow",
        lifecycle_state="ACTIVE",
        tags={"project": PROJECT},
        configuration={"source": "audit", "target": "external"},
    )
    backend = FakeBackend(snapshot((drifted,)))

    summary = LiveWorkflow(tmp_path, backend).run(mode="orm", run_id="drift-run")

    assert summary.state == "failed"
    report_path = tmp_path / "reconciliation-report.json"
    report = json.loads(report_path.read_text(encoding="utf-8"))
    assert report["blocked"] == [
        {
            "action": "blocked",
            "address": "module.service_connector.oci_sch_service_connector.flow",
            "reason": "owned_configuration_mismatch",
        }
    ]
    assert report["operator_remediation"]
    assert "private-drifted-id" not in report_path.read_text(encoding="utf-8")


def test_cleanup_failure_prevents_destroy(tmp_path: Path) -> None:
    backend = FakeBackend(snapshot(), cleanup_green=False)

    summary = LiveWorkflow(tmp_path, backend).run(mode="orm", run_id="cleanup-run")

    assert summary.state == "failed"
    assert backend.calls == ["preflight", "apply", "validate", "cleanup"]


def test_nonzero_residuals_fail_after_bounded_retry(tmp_path: Path) -> None:
    backend = FakeBackend(snapshot(), residual_sequence=[["one"], ["one"]])

    summary = LiveWorkflow(tmp_path, backend, residual_attempts=2, residual_interval=0).run(
        mode="orm", run_id="residual-run"
    )

    assert summary.state == "failed"
    assert backend.calls.count("residuals") == 2
    terminal = (tmp_path / "terminal.json").read_text(encoding="utf-8")
    assert "one" not in terminal
