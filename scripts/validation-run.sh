#!/usr/bin/env bash
set -euo pipefail

directory="artifacts/validation"
mode="local"
run_id=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --directory) directory="$2"; shift 2 ;;
    --mode) mode="$2"; shift 2 ;;
    --run-id) run_id="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

python3 - "$directory" "$mode" "$run_id" <<'PY'
import sys
from pathlib import Path

from m11.artifacts import begin_run

directory, mode, run_id = sys.argv[1:]
context = begin_run(Path(directory), mode=mode, run_id=run_id or None)
print(f"validation_run={context['run_id']} mode={context['mode']}")
PY
