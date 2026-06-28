#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/runtime

windows_mode="$(python3 - <<'PY'
import json
print(json.load(open("artifacts/runtime/terraform-output.json"))["effective_modes"]["value"]["windows_mode"])
PY
)"

if [[ "$windows_mode" == "reuse_goad" ]]; then
  if ! terraform -chdir=terraform apply -input=false -auto-approve -var=reuse_goad_action=cleanup > artifacts/runtime/m11-cleanup.log 2>&1; then
    echo "reused_host_cleanup=failed"
    exit 1
  fi
  if ! terraform -chdir=terraform output -json > artifacts/runtime/terraform-output.json 2> artifacts/runtime/m11-cleanup-output.log; then
    echo "reused_host_cleanup_output=failed"
    exit 1
  fi
  REUSE_GOAD_ACTION=cleanup make validate-windows
fi

echo "reused_host_cleanup=green mode=$windows_mode"
