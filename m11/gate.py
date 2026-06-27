"""Unified M11 gate aggregation and reused-host ownership checks."""

from __future__ import annotations

from collections.abc import Iterable, Mapping, Set
from typing import Any


BASE_REQUIRED_GATES = frozenset(
    {
        "manager",
        "linux",
        "fim",
        "bootstrap",
        "windows",
        "audit",
        "flow",
        "opensearch-views",
        "log-analytics",
        "dashboards",
        "network-posture",
        "artifact-hygiene",
    }
)


def required_gates_for_modes(
    modes: Mapping[str, Any], *, allow_disabled_log_analytics: bool = False, post_destroy: bool = False
) -> tuple[set[str], set[str]]:
    """Return immutable-by-construction gate selections for normalized modes."""
    required = set(BASE_REQUIRED_GATES)
    allowed_skips: set[str] = set()
    if modes.get("windows_mode") == "skip":
        allowed_skips.add("windows")
    if not modes.get("log_analytics") and allow_disabled_log_analytics:
        allowed_skips.update({"log-analytics", "dashboards"})
    if modes.get("managed_opensearch"):
        required.add("managed-opensearch")
    if post_destroy:
        required.update({"destroy-guard", "destroy-residual"})
        if modes.get("windows_mode") == "reuse_goad":
            required.add("windows-cleanup")
    return required, allowed_skips


def aggregate_gates(
    gates: Iterable[Mapping[str, Any]],
    required: Set[str],
    allowed_skips: Set[str] | None = None,
) -> dict[str, Any]:
    allowed_skips = allowed_skips or set()
    by_name = {str(gate["gate"]): str(gate["state"]) for gate in gates}
    missing = sorted(required - by_name.keys())
    failed = sorted(
        gate
        for gate in required & by_name.keys()
        if by_name[gate] == "failed" or (by_name[gate] == "skipped" and gate not in allowed_skips)
    )
    return {
        "state": "failed" if missing or failed else "green",
        "missing": missing,
        "failed": failed,
        "gates": dict(sorted(by_name.items())),
    }


def validate_reuse_goad_markers(
    markers: Mapping[str, Mapping[str, Any]],
    project_name: str,
    action: str,
) -> list[str]:
    if action != "cleanup":
        return []
    return sorted(host for host, marker in markers.items() if marker.get("owner") == project_name)


def validate_gate_run_ids(
    gates: Iterable[Mapping[str, Any]], run_id: str
) -> tuple[list[Mapping[str, Any]], list[str]]:
    """Separate current-run gates from stale or unbound documents."""
    valid: list[Mapping[str, Any]] = []
    stale: list[str] = []
    for gate in gates:
        if gate.get("run_id") == run_id:
            valid.append(gate)
        else:
            stale.append(str(gate.get("gate", "<unknown>")))
    return valid, sorted(stale)


def network_posture_failures(outputs: Mapping[str, Any]) -> list[str]:
    """Return boundary roles that violate bastion-only public reachability."""
    failures: list[str] = []
    if not (outputs.get("bastion_public_ip") or {}).get("value"):
        failures.append("bastion")
    for role, key in (
        ("wazuh", "wazuh_public_ip"),
        ("ol9", "ol9_agent_public_ip"),
        ("ubuntu", "ubuntu_agent_public_ip"),
    ):
        if (outputs.get(key) or {}).get("value"):
            failures.append(role)
    return failures
