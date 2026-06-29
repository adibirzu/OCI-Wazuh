#!/usr/bin/env python3
"""Emit a redacted cross-service inventory of project-owned OCI residuals."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from m11.residuals import logical_residuals
from m11.secure_subprocess import run_quiet


PROJECT_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,62}$")


def _tfvar(name: str) -> str:
    path = ROOT / "terraform/terraform.tfvars"
    if not path.is_file():
        return ""
    pattern = re.compile(rf'^\s*{re.escape(name)}\s*=\s*"([^"\n]+)"\s*$')
    for line in path.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match:
            return match.group(1)
    return ""


def _oci(profile: str, *arguments: str) -> list[str]:
    command = ["oci"]
    if profile:
        command.extend(("--profile", profile))
    command.extend(arguments)
    return command


def _json(command: list[str], label: str) -> Any:
    result = run_quiet(
        command,
        label,
        diagnostic_path=ROOT / "artifacts/runtime/m11-residual-command.log",
    )
    return json.loads(result.stdout)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-name", required=True)
    parser.add_argument("--profile", default=os.environ.get("OCI_CONFIG_PROFILE", ""))
    args = parser.parse_args()
    if not PROJECT_PATTERN.fullmatch(args.project_name):
        raise ValueError("invalid project name")

    compartment = (
        os.environ.get("TF_VAR_compartment_ocid", "")
        or os.environ.get("TF_VAR_compartment_id", "")
        or _tfvar("compartment_ocid")
        or _tfvar("compartment_id")
    )
    tenancy = (
        os.environ.get("TF_VAR_tenancy_ocid", "")
        or os.environ.get("TF_VAR_tenancy_id", "")
        or _tfvar("tenancy_ocid")
        or _tfvar("tenancy_id")
    )
    namespace = os.environ.get("TF_VAR_log_analytics_namespace", "") or _tfvar(
        "log_analytics_namespace"
    )
    if not compartment or not tenancy:
        raise RuntimeError("residual inventory requires tenancy and compartment inputs")
    if not namespace:
        namespaces = _json(
            _oci(
                args.profile,
                "log-analytics",
                "namespace",
                "list",
                "--compartment-id",
                tenancy,
                "--all",
            ),
            "OCI Log Analytics namespace inventory",
        )
        items = namespaces.get("data", {}).get("items", [])
        namespace = str(items[0].get("namespace-name", "")) if len(items) == 1 else ""
    if not namespace:
        raise RuntimeError("residual inventory could not resolve Log Analytics namespace")

    query = (
        "query all resources where "
        f"(freeformTags.key = 'project' && freeformTags.value = '{args.project_name}')"
    )
    search = _json(
        _oci(
            args.profile,
            "search",
            "resource",
            "structured-search",
            "--query-text",
            query,
            "--limit",
            "1000",
        ),
        "OCI residual resource search",
    )
    log_analytics = _json(
        _oci(
            args.profile,
            "log-analytics",
            "log-group",
            "list",
            "--namespace-name",
            namespace,
            "--compartment-id",
            compartment,
            "--all",
        ),
        "OCI residual Log Analytics inventory",
    )
    dashboards = _json(
        _oci(
            args.profile,
            "management-dashboard",
            "dashboard",
            "list",
            "--compartment-id",
            compartment,
            "--all",
        ),
        "OCI residual Management Dashboard inventory",
    )
    saved_searches = _json(
        _oci(
            args.profile,
            "management-dashboard",
            "saved-search",
            "list",
            "--compartment-id",
            compartment,
            "--all",
        ),
        "OCI residual Management Saved Search inventory",
    )
    print(
        json.dumps(
            {
                "data": {
                    "items": logical_residuals(
                        search,
                        log_analytics,
                        args.project_name,
                        dashboards,
                        saved_searches,
                    )
                }
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
