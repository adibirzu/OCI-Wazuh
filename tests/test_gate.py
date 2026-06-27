from pathlib import Path

from m11.gate import (
    aggregate_gates,
    network_posture_failures,
    required_gates_for_modes,
    validate_gate_run_ids,
    validate_reuse_goad_markers,
)


def test_gate_aggregation_requires_every_selected_capability() -> None:
    gates = [
        {"gate": "manager", "state": "green"},
        {"gate": "linux", "state": "green"},
        {"gate": "windows", "state": "skipped"},
    ]

    summary = aggregate_gates(gates, required={"manager", "linux"}, allowed_skips={"windows"})

    assert summary["state"] == "green"
    assert summary["failed"] == []


def test_gate_aggregation_fails_missing_failed_or_unapproved_skip() -> None:
    gates = [
        {"gate": "manager", "state": "green"},
        {"gate": "windows", "state": "skipped"},
        {"gate": "audit", "state": "failed"},
    ]

    summary = aggregate_gates(gates, required={"manager", "linux", "windows", "audit"})

    assert summary["state"] == "failed"
    assert summary["missing"] == ["linux"]
    assert summary["failed"] == ["audit", "windows"]


def test_reuse_goad_cleanup_rejects_remaining_project_owned_markers() -> None:
    markers = {
        "dc01": {"owner": "oci-wazuh-demo", "components": ["wazuh-agent"]},
        "dc02": {"owner": "pre-existing", "components": ["sysmon"]},
    }

    assert validate_reuse_goad_markers(markers, project_name="oci-wazuh-demo", action="cleanup") == ["dc01"]
    assert validate_reuse_goad_markers(markers, project_name="oci-wazuh-demo", action="install") == []


def test_required_gates_follow_selected_optional_modes() -> None:
    required, allowed_skips = required_gates_for_modes(
        {"windows_mode": "skip", "log_analytics": True, "managed_opensearch": False}
    )

    assert {"bootstrap", "opensearch-views", "log-analytics", "dashboards"} <= required
    assert "managed-opensearch" not in required
    assert allowed_skips == {"windows"}

    selected, selected_skips = required_gates_for_modes(
        {"windows_mode": "install_goad", "log_analytics": False, "managed_opensearch": True},
        allow_disabled_log_analytics=True,
        post_destroy=True,
    )
    assert "managed-opensearch" in selected
    assert {"destroy-guard", "destroy-residual"} <= selected
    assert selected_skips == {"log-analytics", "dashboards"}

    reused, _ = required_gates_for_modes(
        {"windows_mode": "reuse_goad", "log_analytics": True, "managed_opensearch": False},
        post_destroy=True,
    )
    assert "windows-cleanup" in reused


def test_gate_documents_from_another_run_are_rejected() -> None:
    gates = [
        {"gate": "manager", "state": "green", "run_id": "current"},
        {"gate": "audit", "state": "green", "run_id": "stale"},
    ]

    valid, stale = validate_gate_run_ids(gates, "current")

    assert valid == [{"gate": "manager", "state": "green", "run_id": "current"}]
    assert stale == ["audit"]


def test_network_posture_requires_bastion_only_public_access() -> None:
    outputs = {
        "bastion_public_ip": {"value": "<PUBLIC>"},
        "wazuh_public_ip": {"value": None},
        "ol9_agent_public_ip": {"value": None},
        "ubuntu_agent_public_ip": {"value": None},
    }

    assert network_posture_failures(outputs) == []
    assert network_posture_failures({**outputs, "wazuh_public_ip": {"value": "<PUBLIC>"}}) == ["wazuh"]


def test_real_log_evidence_is_bound_to_current_run() -> None:
    script = (Path(__file__).resolve().parents[1] / "scripts/validate-real-oci-logs.sh").read_text(encoding="utf-8")

    assert "run_id=" in script
    assert "run_started=" in script
