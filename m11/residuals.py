"""Build redacted logical residual inventories across OCI search surfaces."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import Any


ABSENT_STATES = frozenset({"DELETED", "DELETING", "TERMINATED", "TERMINATING"})


def _items(payload: Mapping[str, Any]) -> Sequence[Mapping[str, Any]]:
    data = payload.get("data", {})
    raw = data.get("items", []) if isinstance(data, Mapping) else data
    if not isinstance(raw, Sequence) or isinstance(raw, (str, bytes)):
        raise ValueError("residual inventory has invalid items")
    if not all(isinstance(item, Mapping) for item in raw):
        raise ValueError("residual inventory item is invalid")
    return raw


def _token(resource_type: str, name: str) -> dict[str, str]:
    if not resource_type or not name:
        raise ValueError("residual inventory item lacks type or name")
    return {"identifier": f"{resource_type}:{name}"}


def logical_residuals(
    search_payload: Mapping[str, Any],
    log_analytics_payload: Mapping[str, Any],
    project_name: str,
    dashboard_payload: Mapping[str, Any] | None = None,
    saved_search_payload: Mapping[str, Any] | None = None,
) -> list[dict[str, str]]:
    """Return logical tokens only; never propagate OCI resource identifiers.

    Resource Search is eventually consistent for Management Dashboard content.
    When the service inventories are supplied, they replace that stale surface for
    dashboard and saved-search resource types.
    """
    residuals: list[dict[str, str]] = []
    for item in _items(search_payload):
        tags = item.get("freeform-tags", item.get("freeform_tags", {}))
        state = str(item.get("lifecycle-state", item.get("lifecycle_state", ""))).upper()
        if not isinstance(tags, Mapping) or tags.get("project") != project_name or state in ABSENT_STATES:
            continue
        resource_type = str(item.get("resource-type", item.get("resource_type", "")))
        uses_authoritative_inventory = (
            resource_type == "ManagementDashboard" and dashboard_payload is not None
        ) or (
            resource_type == "ManagementSavedSearch" and saved_search_payload is not None
        )
        if uses_authoritative_inventory:
            continue
        residuals.append(
            _token(
                resource_type,
                str(item.get("display-name", item.get("display_name", item.get("name", "")))),
            )
        )
    for item in _items(log_analytics_payload):
        tags = item.get("freeform-tags", item.get("freeform_tags", {}))
        if not isinstance(tags, Mapping) or tags.get("project") != project_name:
            continue
        residuals.append(
            _token(
                "LogAnalyticsLogGroup",
                str(item.get("display-name", item.get("display_name", ""))),
            )
        )
    for resource_type, payload in (
        ("ManagementDashboard", dashboard_payload),
        ("ManagementSavedSearch", saved_search_payload),
    ):
        if payload is None:
            continue
        for item in _items(payload):
            tags = item.get("freeform-tags", item.get("freeform_tags", {}))
            if not isinstance(tags, Mapping) or tags.get("project") != project_name:
                continue
            residuals.append(
                _token(
                    resource_type,
                    str(item.get("display-name", item.get("display_name", item.get("name", "")))),
                )
            )
    return [
        {"identifier": identifier}
        for identifier in sorted({item["identifier"] for item in residuals})
    ]
