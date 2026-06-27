"""Pure, fail-closed reconciliation and Service Connector capacity decisions."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from typing import Any, Mapping, Sequence


SUPPORTED_RESOURCE_TYPES = frozenset(
    {
        "oci_identity_dynamic_group",
        "oci_identity_policy",
        "oci_logging_log_group",
        "oci_logging_log",
        "oci_logging_unified_agent_configuration",
        "oci_sch_service_connector",
        "oci_streaming_stream",
        "oci_objectstorage_object",
        "oci_management_dashboard_management_dashboards_import",
    }
)


def configuration_fingerprint(configuration: Mapping[str, Any]) -> str:
    """Return a deterministic digest without retaining or emitting raw values."""
    encoded = json.dumps(configuration, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class ExpectedResource:
    address: str
    resource_type: str
    name: str
    tags: Mapping[str, str]
    configuration: Mapping[str, Any]


@dataclass(frozen=True)
class ObservedResource:
    resource_id: str
    resource_type: str
    name: str
    lifecycle_state: str
    tags: Mapping[str, str]
    configuration: Mapping[str, Any]
    importable: bool = True


@dataclass(frozen=True)
class ReconciliationDecision:
    address: str
    action: str
    reason: str
    resource_id: str | None = None


@dataclass(frozen=True)
class ReconciliationReport:
    decisions: tuple[ReconciliationDecision, ...]
    safe_to_apply: bool


@dataclass(frozen=True)
class ConnectorCapacity:
    limit: int
    active_count: int

    def __post_init__(self) -> None:
        if self.limit < 0 or self.active_count < 0:
            raise ValueError("connector capacity values must be non-negative")


def _decision_for(
    expected: ExpectedResource,
    observed: Sequence[ObservedResource],
    project_name: str,
) -> ReconciliationDecision:
    if expected.resource_type not in SUPPORTED_RESOURCE_TYPES:
        return ReconciliationDecision(expected.address, "blocked", "unsupported_resource_type")

    active = tuple(
        candidate
        for candidate in observed
        if candidate.resource_type == expected.resource_type
        and candidate.name == expected.name
        and candidate.lifecycle_state.upper() not in {"DELETED", "DELETING", "TERMINATED"}
    )
    if not active:
        return ReconciliationDecision(expected.address, "create", "no_active_match")

    owned = tuple(candidate for candidate in active if candidate.tags.get("project") == project_name)
    if not owned:
        return ReconciliationDecision(expected.address, "externally_owned", "name_only_collision")

    expected_fingerprint = configuration_fingerprint(expected.configuration)
    exact = tuple(
        candidate
        for candidate in owned
        if configuration_fingerprint(candidate.configuration) == expected_fingerprint
    )
    if len(exact) > 1:
        return ReconciliationDecision(expected.address, "blocked", "ambiguous_exact_matches")
    if not exact:
        return ReconciliationDecision(expected.address, "blocked", "owned_configuration_mismatch")
    if not exact[0].importable:
        return ReconciliationDecision(expected.address, "blocked", "provider_import_unsupported")
    return ReconciliationDecision(expected.address, "import", "owned_configuration_match", exact[0].resource_id)


def reconcile_resources(
    expected: Sequence[ExpectedResource],
    observed: Sequence[ObservedResource],
    project_name: str,
) -> ReconciliationReport:
    """Classify resources without mutating either input collection."""
    decisions = tuple(_decision_for(item, observed, project_name) for item in expected)
    safe = all(decision.action in {"create", "import"} for decision in decisions)
    return ReconciliationReport(decisions=decisions, safe_to_apply=safe)


def decide_connector_capacity(
    expected: ExpectedResource,
    observed: Sequence[ObservedResource],
    capacity: ConnectorCapacity,
    project_name: str,
) -> ReconciliationDecision:
    """Prefer exact reuse; otherwise require one available connector slot."""
    report = reconcile_resources([expected], observed, project_name)
    decision = report.decisions[0]
    if decision.action != "create":
        return decision
    if capacity.active_count < capacity.limit:
        return decision
    return ReconciliationDecision(expected.address, "blocked", "service_connector_quota_exhausted")
