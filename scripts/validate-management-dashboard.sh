#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
outputs="$repo_root/artifacts/runtime/terraform-output.json"
evidence="$repo_root/artifacts/validation/M8-management-dashboard.txt"
profile="${OCI_PROFILE:-${OCI_CLI_PROFILE:-DEFAULT}}"

value() {
  python3 - "$outputs" "$1" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))[sys.argv[2]]["value"])
PY
}

project_name="$(value project_name)"
compartment_id="${COMPARTMENT_OCID:-}"
if [[ -z "$compartment_id" ]]; then
  if [[ ! -f "$repo_root/terraform/terraform.tfvars" ]]; then
    echo "missing compartment OCID; set COMPARTMENT_OCID" >&2
    exit 2
  fi
  compartment_id="$(awk -F= '/^(compartment_ocid|compartment_id)[[:space:]]*=/{gsub(/[ "]/ ,"",$2); if ($2 != "") {print $2; exit}}' "$repo_root/terraform/terraform.tfvars")"
fi
test -n "$compartment_id"

count="$(oci --profile "$profile" management-dashboard dashboard list \
  --compartment-id "$compartment_id" --all \
  --query "length(data.items[?\"display-name\"=='${project_name}-correlation'])" \
  --raw-output)"

{
  echo "management_dashboard=$([[ "$count" -eq 1 ]] && echo green || echo failed)"
  echo "dashboard_name=${project_name}-correlation"
  echo "dashboard_count=$count"
} >"$evidence"
cat "$evidence"
test "$count" -eq 1
