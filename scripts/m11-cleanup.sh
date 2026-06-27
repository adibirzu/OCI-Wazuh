#!/usr/bin/env bash
set -euo pipefail

windows_mode="$(python3 - <<'PY'
import json
print(json.load(open("artifacts/runtime/terraform-output.json"))["effective_modes"]["value"]["windows_mode"])
PY
)"

if [[ "$windows_mode" == "reuse_goad" ]]; then
  terraform -chdir=terraform apply -input=false -auto-approve -var=reuse_goad_action=cleanup
  terraform -chdir=terraform output -json > artifacts/runtime/terraform-output.json
  REUSE_GOAD_ACTION=cleanup make validate-windows
fi

echo "reused_host_cleanup=green mode=$windows_mode"
