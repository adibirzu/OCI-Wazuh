#!/usr/bin/env python3
"""Aggregate live validation evidence into the release-blocking M11 gate."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from m11.artifacts import write_gate  # noqa: E402
from m11.gate import (  # noqa: E402
    aggregate_gates,
    network_posture_failures,
    required_gates_for_modes,
    validate_gate_run_ids,
)
from m11.redaction import find_runtime_topology  # noqa: E402

ARTIFACTS = ROOT / "artifacts/validation"
RUNTIME_OUTPUTS = ROOT / "artifacts/runtime/terraform-output.json"


def contains(path: Path, *needles: str) -> bool:
    if not path.is_file():
        return False
    content = path.read_text(encoding="utf-8", errors="replace")
    return all(needle in content for needle in needles)


def load_existing_gates() -> list[dict[str, object]]:
    gates = []
    for path in ARTIFACTS.glob("*.json"):
        payload = json.loads(path.read_text(encoding="utf-8"))
        if "gate" in payload and "state" in payload:
            gates.append(payload)
    return gates


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--allow-disabled-log-analytics", action="store_true")
    parser.add_argument("--post-destroy", action="store_true")
    args = parser.parse_args()

    context = json.loads((ARTIFACTS / "_run.json").read_text(encoding="utf-8"))
    outputs = json.loads(RUNTIME_OUTPUTS.read_text(encoding="utf-8"))
    modes = outputs["effective_modes"]["value"]

    real_logs = ARTIFACTS / "M6-M7-real-oci-logs.txt"
    run_binding = (f"run_id={context['run_id']}", f"run_started={context['timestamp']}")
    write_gate(
        ARTIFACTS,
        context,
        "audit",
        "green" if contains(real_logs, *run_binding, "audit_rule_100000=green") else "failed",
        {"freshness": "after-run-start"},
    )
    write_gate(
        ARTIFACTS,
        context,
        "flow",
        "green" if contains(real_logs, *run_binding, "flow_rule_100100=green") else "failed",
        {"freshness": "after-run-start"},
    )

    network_failures = network_posture_failures(outputs)
    write_gate(
        ARTIFACTS,
        context,
        "network-posture",
        "failed" if network_failures else "green",
        {"bastion_only": not network_failures, "violations": network_failures},
    )

    log_analytics_enabled = bool(modes["log_analytics"])
    la_evidence = ARTIFACTS / "M8-log-analytics-freshness.txt"
    la_needles = [
        "wazuh_alerts_oci_logging_last_window=ready",
        "wazuh_alerts_log_analytics_last_window=ready",
    ]
    if modes["windows_mode"] != "skip":
        la_needles.extend([
            "windows_events_oci_logging_last_window=ready",
            "windows_events_log_analytics_last_window=ready",
        ])
    la_green = contains(la_evidence, *la_needles)
    la_state = "green" if la_green else "skipped" if not log_analytics_enabled else "failed"
    write_gate(ARTIFACTS, context, "log-analytics", la_state, {"selected": log_analytics_enabled})

    dashboard_evidence = ARTIFACTS / "M8-management-dashboard.txt"
    dashboard_state = "green" if contains(dashboard_evidence, "management_dashboard=green") else "skipped" if not log_analytics_enabled else "failed"
    write_gate(ARTIFACTS, context, "dashboards", dashboard_state, {"selected": log_analytics_enabled})

    topology_files = sorted(
        path.name
        for path in ARTIFACTS.iterdir()
        if path.is_file()
        and path.name != "artifact-hygiene.json"
        and find_runtime_topology(path.read_text(encoding="utf-8", errors="replace"))
    )
    _, stale_gates = validate_gate_run_ids(load_existing_gates(), context["run_id"])
    write_gate(
        ARTIFACTS,
        context,
        "artifact-hygiene",
        "failed" if topology_files or stale_gates else "green",
        {"files_with_topology": topology_files, "stale_gates": stale_gates},
    )

    required, allowed_skips = required_gates_for_modes(
        modes,
        allow_disabled_log_analytics=args.allow_disabled_log_analytics,
        post_destroy=args.post_destroy,
    )

    current_gates, _ = validate_gate_run_ids(load_existing_gates(), context["run_id"])
    summary = aggregate_gates(current_gates, required=required, allowed_skips=allowed_skips)
    details = {
        **summary,
        "ingestion_mode": modes["ingestion_mode"],
        "network_mode": modes["network_mode"],
        "post_destroy": args.post_destroy,
        "windows_mode": modes["windows_mode"],
    }
    write_gate(ARTIFACTS, context, "M11-summary", summary["state"], details)
    print(f"m11={summary['state']} missing={','.join(summary['missing'])} failed={','.join(summary['failed'])}")
    return 0 if summary["state"] == "green" else 1


if __name__ == "__main__":
    raise SystemExit(main())
