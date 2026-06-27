"""Build a deterministic reconciliation snapshot from Terraform and OCI JSON."""

from __future__ import annotations

import json
from collections.abc import Iterator, Mapping, Sequence
from typing import Any

from m11.live_workflow import PreflightSnapshot
from m11.reconciliation import (
    SUPPORTED_RESOURCE_TYPES,
    ConnectorCapacity,
    ExpectedResource,
    ObservedResource,
)


OCI_TO_TERRAFORM_TYPE = {
    "DynamicGroup": "oci_identity_dynamic_group",
    "Policy": "oci_identity_policy",
    "LogGroup": "oci_logging_log_group",
    "Log": "oci_logging_log",
    "LogConfiguration": "oci_logging_unified_agent_configuration",
    "ServiceConnector": "oci_sch_service_connector",
    "Stream": "oci_streaming_stream",
    "Object": "oci_objectstorage_object",
    "ManagementDashboard": "oci_management_dashboard_management_dashboards_import",
}

NON_IMPORTABLE_TYPES = frozenset(
    {
        "oci_objectstorage_object",
        "oci_management_dashboard_management_dashboards_import",
    }
)


def _resources(module: Mapping[str, Any]) -> Iterator[Mapping[str, Any]]:
    yield from module.get("resources", [])
    for child in module.get("child_modules", []):
        yield from _resources(child)


def _name(values: Mapping[str, Any]) -> str:
    for key in ("display_name", "name", "bucket_name", "object"):
        value = values.get(key)
        if isinstance(value, str) and value:
            return value
    dashboard = _dashboard(values)
    display_name = dashboard.get("displayName")
    if isinstance(display_name, str):
        return display_name
    return ""


def _dashboard(value: Mapping[str, Any]) -> Mapping[str, Any]:
    raw = value.get("import_details")
    if not isinstance(raw, str):
        return {}
    try:
        payload = json.loads(raw)
    except (TypeError, ValueError):
        return {}
    dashboards = payload.get("dashboards", []) if isinstance(payload, Mapping) else []
    if not dashboards or not isinstance(dashboards[0], Mapping):
        return {}
    return dashboards[0]


def _tags(value: Mapping[str, Any]) -> dict[str, str]:
    raw = value.get("freeform_tags", value.get("freeform-tags", {}))
    if not raw:
        raw = value.get("metadata", {})
    if not raw:
        raw = _dashboard(value).get("freeformTags", {})
    if not isinstance(raw, Mapping):
        return {}
    return {str(key): str(item) for key, item in raw.items()}


def _expected_resources(plan: Mapping[str, Any], project_name: str) -> tuple[ExpectedResource, ...]:
    try:
        root = plan["planned_values"]["root_module"]
    except (KeyError, TypeError) as exc:
        raise ValueError("Terraform plan is missing planned_values.root_module") from exc

    expected: list[ExpectedResource] = []
    for resource in _resources(root):
        resource_type = resource.get("type")
        if resource_type not in SUPPORTED_RESOURCE_TYPES:
            continue
        values = resource.get("values") or {}
        tags = _tags(values)
        fingerprint = tags.get("configuration_fingerprint", "")
        name = _name(values)
        if tags.get("project") != project_name or not fingerprint or not name:
            raise ValueError(
                f"supported resource {resource.get('address', '<unknown>')} lacks project fingerprint or name"
            )
        expected.append(
            ExpectedResource(
                address=str(resource["address"]),
                resource_type=str(resource_type),
                name=name,
                tags=tags,
                configuration={"fingerprint": fingerprint},
            )
        )
    return tuple(expected)


def build_preflight_snapshot(
    terraform_plan: Mapping[str, Any],
    search_items: Sequence[Mapping[str, Any]],
    project_name: str,
    *,
    connector_limit: int,
) -> PreflightSnapshot:
    """Create immutable inputs for reconciliation; perform no mutations or imports."""
    if connector_limit < 1:
        raise ValueError("connector_limit must be a positive queried limit")
    expected = _expected_resources(terraform_plan, project_name)
    expected_keys = {(item.resource_type, item.name) for item in expected}
    observed: list[ObservedResource] = []
    active_connectors = 0

    for item in search_items:
        oci_type = str(item.get("resource-type", item.get("resource_type", "")))
        resource_type = OCI_TO_TERRAFORM_TYPE.get(oci_type, oci_type)
        state = str(item.get("lifecycle-state", item.get("lifecycle_state", "")))
        if resource_type == "oci_sch_service_connector" and state.upper() not in {
            "DELETED",
            "DELETING",
            "TERMINATED",
        }:
            active_connectors += 1

        name = str(item.get("display-name", item.get("display_name", item.get("name", ""))))
        if (resource_type, name) not in expected_keys:
            continue
        tags = _tags(item)
        observed.append(
            ObservedResource(
                resource_id=str(item.get("identifier", item.get("id", ""))),
                resource_type=resource_type,
                name=name,
                lifecycle_state=state,
                tags=tags,
                configuration={"fingerprint": tags.get("configuration_fingerprint", "")},
                importable=resource_type not in NON_IMPORTABLE_TYPES,
            )
        )

    return PreflightSnapshot(
        project_name=project_name,
        expected=expected,
        observed=tuple(observed),
        connector_capacity=ConnectorCapacity(limit=connector_limit, active_count=active_connectors),
    )
