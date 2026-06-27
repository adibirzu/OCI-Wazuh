"""Pure ownership evaluation for Terraform destroy plans."""

from __future__ import annotations

import json
import time
from collections.abc import Callable, Sequence
from typing import Any


CHILD_PARENT_FIELDS = {
    "oci_core_network_security_group_security_rule": ("network_security_group_id",),
    "oci_objectstorage_object": ("bucket",),
}
LOCAL_ONLY_TYPES = frozenset({"random_id", "terraform_data"})


def _display_name(before: dict[str, Any]) -> str:
    for key in ("display_name", "name", "bucket_name"):
        value = before.get(key)
        if isinstance(value, str) and value:
            return value
    return ""


def _deletes(change: dict[str, Any]) -> bool:
    return "delete" in ((change.get("change") or {}).get("actions") or [])


def _embedded_project_tag(resource_type: str, before: dict[str, Any], project_name: str) -> bool:
    if resource_type != "oci_management_dashboard_management_dashboards_import":
        return False
    raw = before.get("import_details")
    if not isinstance(raw, str):
        return False
    try:
        payload = json.loads(raw)
    except (TypeError, ValueError):
        return False
    dashboards = payload.get("dashboards", []) if isinstance(payload, dict) else []
    return any(
        isinstance(item, dict)
        and isinstance(item.get("freeformTags"), dict)
        and item["freeformTags"].get("project") == project_name
        for item in dashboards
    )


def _owned_references(before: dict[str, Any]) -> set[str]:
    return {
        value
        for key in ("id", "display_name", "name", "bucket_name")
        if isinstance((value := before.get(key)), str) and value
    }


def evaluate_destroy_plan(plan: dict[str, Any], project_name: str) -> dict[str, Any]:
    """Return a serializable decision without mutating the source plan."""
    changes = [change for change in plan.get("resource_changes", []) if _deletes(change)]
    candidates = []
    for change in changes:
        before = (change.get("change") or {}).get("before") or {}
        tags = before.get("freeform_tags") or {}
        tagged = isinstance(tags, dict) and tags.get("project") == project_name
        name = _display_name(before)
        named = name.startswith(f"{project_name}-") or name == project_name
        resource_type = str(change.get("type", "<unknown>"))
        embedded = _embedded_project_tag(resource_type, before, project_name)
        candidates.append((change, before, tagged, named, embedded))

    owned_references = {
        reference
        for _, before, tagged, named, embedded in candidates
        if tagged or named or embedded
        for reference in _owned_references(before)
    }

    blocked: list[dict[str, Any]] = []
    for change, before, tagged, named, embedded in candidates:
        resource_type = change.get("type", "<unknown>")
        parent_fields = CHILD_PARENT_FIELDS.get(resource_type, ())
        parent_owned = any(before.get(field) in owned_references for field in parent_fields)
        local_only = resource_type in LOCAL_ONLY_TYPES
        allowed = tagged or named or embedded or parent_owned or local_only
        if not allowed:
            blocked.append(
                {
                    "address": change.get("address", "<unknown>"),
                    "type": resource_type,
                    "tagged_project": tagged,
                    "named_project": named,
                    "embedded_project": embedded,
                    "parent_owned": parent_owned,
                    "local_only": local_only,
                    "ok": False,
                }
            )

    return {
        "project_name": project_name,
        "delete_count": len(changes),
        "blocked": blocked,
        "ok": not blocked,
    }


def wait_for_zero_residuals(
    search: Callable[[], Sequence[str]],
    *,
    attempts: int,
    interval_seconds: float,
    sleep: Callable[[float], None] = time.sleep,
) -> dict[str, Any]:
    """Poll a residual-resource search and return counts, never identifiers."""
    if attempts < 1:
        raise ValueError("attempts must be at least one")
    residual_count = 0
    for attempt in range(1, attempts + 1):
        residual_count = len(tuple(search()))
        if residual_count == 0:
            return {"ok": True, "attempts": attempt, "residual_count": 0}
        if attempt < attempts:
            sleep(interval_seconds)
    return {"ok": False, "attempts": attempts, "residual_count": residual_count}
