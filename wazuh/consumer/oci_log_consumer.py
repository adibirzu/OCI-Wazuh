#!/usr/bin/env python3
"""Consume OCI log events and write normalized JSON lines for Wazuh."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def normalize_event(raw: dict[str, Any], source: str) -> dict[str, Any]:
    data = raw.get("data", raw)
    normalized = {
        "source": source,
        "time": data.get("eventTime") or raw.get("eventTime") or datetime.now(timezone.utc).isoformat(),
        "eventType": data.get("eventType") or data.get("type"),
        "principalName": data.get("principalName") or data.get("identity", {}).get("principalName"),
        "sourceIp": data.get("sourceIpAddress") or data.get("sourceIp"),
        "compartmentId": data.get("compartmentId"),
        "raw": raw,
    }
    if source == "flow":
        normalized.update({
            "srcaddr": data.get("srcaddr"),
            "dstaddr": data.get("dstaddr"),
            "srcport": data.get("srcport"),
            "dstport": data.get("dstport"),
            "protocol": data.get("protocol"),
            "action": data.get("action"),
            "bytes": data.get("bytes"),
            "packets": data.get("packets"),
        })
    return {key: value for key, value in normalized.items() if value is not None}


def normalize_file(input_path: Path, output_path: Path, source: str) -> int:
    count = 0
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with input_path.open("r", encoding="utf-8") as source_file, output_path.open("a", encoding="utf-8") as sink:
        for line in source_file:
            if not line.strip():
                continue
            sink.write(json.dumps(normalize_event(json.loads(line), source), separators=(",", ":")) + "\n")
            count += 1
    return count


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["streaming", "object_storage", "direct_api"], default="streaming")
    parser.add_argument("--source", choices=["audit", "flow"], required=True)
    parser.add_argument("--input-file", type=Path, help="Development/test input JSONL file.")
    parser.add_argument("--output-file", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.input_file:
        count = normalize_file(args.input_file, args.output_file, args.source)
        print(f"normalized={count}")
        return 0
    print("Live OCI consumption is configured by Ansible in deployment milestones.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
