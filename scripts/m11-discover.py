#!/usr/bin/env python3
"""Build a runtime-only reconciliation snapshot from Terraform and OCI CLI."""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import asdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from m11.discovery import (
    build_preflight_snapshot,
    normalize_log_analytics_groups,
    normalize_logging_logs,
)
from m11.secure_subprocess import classify_terraform_error, run_quiet


def run_json(
    command: list[str],
    *,
    label: str,
    stdout_path: Path | None = None,
) -> Any:
    result = run_quiet(
        command,
        label,
        diagnostic_path=ROOT / "artifacts/runtime/m11-discovery-command.log",
    )
    if stdout_path is not None:
        stdout_path.write_text(result.stdout, encoding="utf-8")
    return json.loads(result.stdout)


def oci_command(profile: str, *arguments: str) -> list[str]:
    command = ["oci"]
    if profile:
        command.extend(("--profile", profile))
    command.extend(arguments)
    return command


def planned_resource_values(plan: dict[str, Any], resource_type: str) -> tuple[dict[str, Any], ...]:
    root = plan.get("planned_values", {}).get("root_module", {})
    modules = [root]
    matches: list[dict[str, Any]] = []
    while modules:
        module = modules.pop()
        modules.extend(module.get("child_modules", []))
        for resource in module.get("resources", []):
            if resource.get("type") == resource_type:
                values = resource.get("values")
                if values is not None and not isinstance(values, dict):
                    raise ValueError("planned Log Analytics group values are invalid")
                if values is not None:
                    matches.append(values)
    return tuple(matches)


def planned_log_analytics_group(plan: dict[str, Any]) -> dict[str, Any] | None:
    groups = planned_resource_values(plan, "oci_log_analytics_log_analytics_log_group")
    if len(groups) > 1:
        raise ValueError("multiple planned Log Analytics groups are unsupported")
    return groups[0] if groups else None


def planned_logging_groups(plan: dict[str, Any]) -> tuple[dict[str, Any], ...]:
    return planned_resource_values(plan, "oci_logging_log_group")


def connector_limit(profile: str, tenancy_id: str) -> int:
    explicit = os.environ.get("M11_SERVICE_CONNECTOR_LIMIT", "")
    if explicit:
        value = int(explicit)
        if value < 1:
            raise ValueError("M11_SERVICE_CONNECTOR_LIMIT must be positive")
        return value
    payload = run_json(
        oci_command(
            profile,
            "limits",
            "value",
            "list",
            "--service-name",
            os.environ.get("M11_SERVICE_CONNECTOR_LIMIT_SERVICE", "service-connector-hub"),
            "--compartment-id",
            tenancy_id,
            "--scope-type",
            "REGION",
            "--all",
        ),
        label="OCI Service Connector limit query",
    )
    values = [
        int(item["value"])
        for item in payload.get("data", [])
        if "connector" in str(item.get("name", "")).lower() and int(item.get("value", 0)) > 0
    ]
    if not values:
        raise RuntimeError("Service Connector limit query returned no usable capacity")
    return max(values)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("local", "orm"), required=True)
    parser.add_argument("--profile", default="")
    parser.add_argument("--project-name", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    if args.mode == "orm" and args.profile:
        raise ValueError("ORM discovery must remain profile-free")
    tenancy = os.environ.get("TF_VAR_tenancy_ocid", "") or os.environ.get("TF_VAR_tenancy_id", "")
    compartment = os.environ.get("TF_VAR_compartment_ocid", "") or os.environ.get("TF_VAR_compartment_id", "")
    if not tenancy or not compartment:
        raise RuntimeError("canonical tenancy and compartment inputs are required for discovery")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    plan_path = args.output.with_suffix(".tfplan")
    plan_json_path = args.output.with_suffix(".plan.json")
    run_quiet(
        ["terraform", "-chdir=terraform", "init", "-backend=false", "-input=false"],
        "Terraform discovery init",
    )
    run_quiet(
        ["terraform", "-chdir=terraform", "plan", "-input=false", f"-out={plan_path.resolve()}"],
        "Terraform discovery plan",
        diagnostic_classifier=classify_terraform_error,
        diagnostic_path=ROOT / "artifacts/runtime/m11-discovery-plan.log",
    )
    plan = run_json(
        ["terraform", "-chdir=terraform", "show", "-json", str(plan_path.resolve())],
        label="Terraform plan rendering",
        stdout_path=plan_json_path,
    )

    # Inventory all accessible resources so name-only and externally owned
    # collisions are visible. build_preflight_snapshot retains only names and
    # types present in the current Terraform plan; raw inventory is not saved.
    query = "query all resources"
    search = run_json(
        oci_command(
            args.profile,
            "search",
            "resource",
            "structured-search",
            "--query-text",
            query,
            "--limit",
            "1000",
        ),
        label="OCI resource search",
    )
    items = list(search.get("data", {}).get("items", []))
    normalized_logs: list[dict[str, Any]] = []
    normalized_log_ids: set[str] = set()
    for logging_group in planned_logging_groups(plan):
        logging_group_name = logging_group.get("display_name", "")
        candidate_groups = [
            item
            for item in items
            if item.get("resource-type") == "LogGroup"
            and item.get("display-name") == logging_group_name
            and item.get("identifier")
        ]
        for candidate_group in candidate_groups:
            group_id = str(candidate_group["identifier"])
            logging_logs = run_json(
                oci_command(
                    args.profile,
                    "logging",
                    "log",
                    "list",
                    "--log-group-id",
                    group_id,
                    "--all",
                ),
                label="OCI Logging log inventory",
            )
            normalized_logs.extend(normalize_logging_logs(logging_logs, group_id))
            normalized_log_ids.update(
                str(item.get("id", "")) for item in logging_logs.get("data", [])
            )
    items = [
        item
        for item in items
        if not (
            item.get("resource-type") == "Log"
            and str(item.get("identifier", "")) in normalized_log_ids
        )
    ]
    items.extend(normalized_logs)
    log_analytics_group = planned_log_analytics_group(plan)
    if log_analytics_group is not None:
        namespace = log_analytics_group.get("namespace", "")
        group_compartment = log_analytics_group.get("compartment_id", "")
        if not namespace or not group_compartment:
            raise RuntimeError("planned Log Analytics group inventory scope is incomplete")
        log_analytics_groups = run_json(
            oci_command(
                args.profile,
                "log-analytics",
                "log-group",
                "list",
                "--namespace-name",
                namespace,
                "--compartment-id",
                group_compartment,
                "--all",
            ),
            label="OCI Log Analytics group inventory",
        )
        items.extend(normalize_log_analytics_groups(log_analytics_groups, namespace))
    snapshot = build_preflight_snapshot(
        plan,
        items,
        args.project_name,
        connector_limit=connector_limit(args.profile, tenancy),
    )
    snapshot_payload = {**asdict(snapshot), "run_id": os.environ.get("M11_RUN_ID", "")}
    args.output.write_text(
        json.dumps(snapshot_payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        f"reconciliation_snapshot=ready expected={len(snapshot.expected)} "
        f"observed={len(snapshot.observed)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
