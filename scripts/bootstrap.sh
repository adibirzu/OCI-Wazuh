#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/validation

status=0

for path in docs/REUSE_MAP.md docs/decisions/REQUIREMENTS.md README.md Makefile terraform/main.tf wazuh/consumer/oci_log_consumer.py; do
  if [[ ! -s "$path" ]]; then
    echo "missing required file: $path"
    status=1
  fi
done

for category in network compute logging SCH; do
  if ! grep -qi "| $category |" docs/REUSE_MAP.md; then
    echo "reuse map missing category: $category"
    status=1
  fi
done

{
  echo "gate=M1"
  echo "status=$([[ "$status" -eq 0 ]] && echo green || echo red)"
  echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > artifacts/validation/M1-bootstrap.txt

exit "$status"
