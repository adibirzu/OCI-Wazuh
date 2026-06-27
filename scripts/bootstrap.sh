#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/validation
bash scripts/validation-run.sh --directory artifacts/validation --mode bootstrap --run-id "${VALIDATION_RUN_ID:-}"

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

python3 - "$status" <<'PY'
import json
import sys
from pathlib import Path

from m11.artifacts import write_gate

directory = Path("artifacts/validation")
context = json.loads((directory / "_run.json").read_text(encoding="utf-8"))
status = int(sys.argv[1])
write_gate(directory, context, "M1-bootstrap", "green" if status == 0 else "failed", {})
PY

exit "$status"
