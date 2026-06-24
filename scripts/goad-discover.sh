#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/validation

tfvars="${TFVARS_FILE:-terraform/terraform.tfvars}"
profile="${OCI_PROFILE:-}"
compartment_id="${COMPARTMENT_OCID:-}"

tfvar_value() {
  local key="$1"
  [[ -f "$tfvars" ]] || return 0
  awk -F= -v k="$key" '$1 ~ "^[[:space:]]*" k "[[:space:]]*$" {gsub(/[ \"]/,"",$2); print $2}' "$tfvars"
}

if [[ -z "$profile" ]]; then
  profile="$(tfvar_value oci_config_profile)"
fi
if [[ -z "$profile" ]]; then
  profile="DEFAULT"
fi

if [[ -z "$compartment_id" ]]; then
  compartment_id="$(tfvar_value compartment_id)"
fi
if [[ -z "$compartment_id" || "$compartment_id" == "<COMPARTMENT_OCID>" ]]; then
  echo "missing compartment_id; set COMPARTMENT_OCID or terraform/terraform.tfvars" >&2
  exit 2
fi

instances_json="artifacts/validation/M5-goad-instances.json"
vcns_json="artifacts/validation/M5-goad-vcns.json"
evidence="artifacts/validation/M5-goad-discovery.txt"

oci --profile "$profile" network vcn list \
  --compartment-id "$compartment_id" \
  --all \
  --output json > "$vcns_json"

oci --profile "$profile" compute instance list \
  --compartment-id "$compartment_id" \
  --all \
  --output json > "$instances_json"

python3 - "$vcns_json" "$instances_json" > "$evidence" <<'PY'
import json
import sys

vcns_path, instances_path = sys.argv[1], sys.argv[2]
expected_hosts = ["braavos", "castelblack", "kingslanding", "meereen", "winterfell"]

with open(vcns_path, encoding="utf-8") as fh:
    vcns = json.load(fh).get("data", [])
with open(instances_path, encoding="utf-8") as fh:
    instances = json.load(fh).get("data", [])

goad_vcns = [
    v for v in vcns
    if "goad" in (v.get("display-name") or "").lower()
    and v.get("lifecycle-state") == "AVAILABLE"
]

instance_by_name = {
    (i.get("display-name") or "").lower(): i
    for i in instances
}

print("m5_goad_discovery=started")
print(f"goad_vcn={'ready' if goad_vcns else 'missing'}")
print(f"goad_vcn_count={len(goad_vcns)}")

ready = bool(goad_vcns)
for host in expected_hosts:
    state = (instance_by_name.get(host) or {}).get("lifecycle-state", "MISSING")
    print(f"host.{host}={state}")
    ready = ready and state == "RUNNING"

print(f"goad_reuse={'ready' if ready else 'not_ready'}")
PY

cat "$evidence"
