#!/usr/bin/env python3
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ARTIFACT = ROOT / "artifacts/validation/destroy-guard.json"
CHILD_TYPES = {
    "oci_core_network_security_group_security_rule",
}


def display_name(before):
    for key in ("display_name", "name", "bucket_name"):
        value = before.get(key)
        if isinstance(value, str) and value:
            return value
    return ""


def freeform_project(before):
    tags = before.get("freeform_tags") or {}
    return tags.get("project") if isinstance(tags, dict) else None


def planned_delete(change):
    actions = (change.get("change") or {}).get("actions") or []
    return "delete" in actions


def before_values(change):
    return (change.get("change") or {}).get("before") or {}


def main():
    if len(sys.argv) < 3:
        raise SystemExit("usage: guard-destroy-plan.py <destroy-plan.json> <project_name>")

    plan_path = Path(sys.argv[1])
    project_name = sys.argv[2]
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    changes = [change for change in plan.get("resource_changes", []) if planned_delete(change)]

    owned_ids = set()
    candidates = []
    blocked = []

    for change in changes:
        before = before_values(change)
        name = display_name(before)
        resource_id = before.get("id")
        tagged = freeform_project(before) == project_name
        named = name.startswith(project_name) or f"{project_name}-" in name
        if tagged or named:
            if isinstance(resource_id, str) and resource_id:
                owned_ids.add(resource_id)
        candidates.append((change, before, tagged, named))

    for change, before, tagged, named in candidates:
        address = change.get("address", "<unknown>")
        resource_type = change.get("type", "<unknown>")
        name = display_name(before)
        parent_owned = False
        if resource_type in CHILD_TYPES:
            parent_id = before.get("network_security_group_id")
            parent_owned = isinstance(parent_id, str) and parent_id in owned_ids

        ok = tagged or named or parent_owned
        record = {
            "address": address,
            "type": resource_type,
            "name": name,
            "tagged_project": tagged,
            "named_project": named,
            "parent_owned": parent_owned,
            "ok": ok,
        }
        if not ok:
            blocked.append(record)

    result = {
        "project_name": project_name,
        "delete_count": len(changes),
        "blocked": blocked,
        "ok": not blocked,
    }
    ARTIFACT.parent.mkdir(parents=True, exist_ok=True)
    ARTIFACT.write_text(json.dumps(result, indent=2), encoding="utf-8")

    if blocked:
        print(f"destroy_guard=blocked artifact={ARTIFACT.relative_to(ROOT)}")
        for item in blocked:
            print(f"blocked_delete address={item['address']} type={item['type']} name={item['name']}")
        return 1

    print(f"destroy_guard=ready delete_count={len(changes)} artifact={ARTIFACT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
