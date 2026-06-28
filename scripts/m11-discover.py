#!/usr/bin/env python3
"""Build a runtime-only reconciliation snapshot from Terraform and OCI CLI."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from dataclasses import asdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from m11.discovery import build_preflight_snapshot


def run_json(command: list[str], *, stdout_path: Path | None = None) -> Any:
    result = subprocess.run(command, check=False, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"discovery command failed: {command[0]}")
    if stdout_path is not None:
        stdout_path.write_text(result.stdout, encoding="utf-8")
    return json.loads(result.stdout)


def oci_command(profile: str, *arguments: str) -> list[str]:
    command = ["oci"]
    if profile:
        command.extend(("--profile", profile))
    command.extend(arguments)
    return command


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
        )
    )
    values = [
        int(item["value"])
        for item in payload.get("data", [])
        if "connector" in str(item.get("name", "")).lower() and int(item.get("value", 0)) > 0
    ]
    if not values:
        raise RuntimeError("Service Connector limit query returned no usable capacity")
    return max(values)


def normalize_connectors(payload: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        {
            "identifier": item.get("id", ""),
            "display-name": item.get("display-name", ""),
            "resource-type": "ServiceConnector",
            "lifecycle-state": item.get("lifecycle-state", ""),
            "freeform-tags": item.get("freeform-tags", {}),
        }
        for item in payload.get("data", {}).get("items", payload.get("data", []))
    ]


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
    subprocess.run(
        ["terraform", "-chdir=terraform", "init", "-backend=false", "-input=false"],
        check=True,
    )
    subprocess.run(
        ["terraform", "-chdir=terraform", "plan", "-input=false", f"-out={plan_path.resolve()}"],
        check=True,
    )
    plan = run_json(
        ["terraform", "-chdir=terraform", "show", "-json", str(plan_path.resolve())],
        stdout_path=plan_json_path,
    )

    # Inventory all accessible resources so name-only and externally owned
    # collisions are visible. build_preflight_snapshot retains only names and
    # types present in the current Terraform plan; raw inventory is not saved.
    query = "query all resources"
    search = run_json(
        oci_command(args.profile, "search", "resource", "structured-search", "--query-text", query, "--all")
    )
    connectors = run_json(
        oci_command(
            args.profile,
            "sch",
            "service-connector",
            "list",
            "--compartment-id",
            compartment,
            "--all",
        )
    )
    items = list(search.get("data", {}).get("items", []))
    known = {str(item.get("identifier", "")) for item in items}
    items.extend(item for item in normalize_connectors(connectors) if item["identifier"] not in known)
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
