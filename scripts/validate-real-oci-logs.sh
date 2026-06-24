#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/wazuh-ssh.sh"

mkdir -p "$REPO_ROOT/artifacts/validation"
evidence="$REPO_ROOT/artifacts/validation/M6-M7-real-oci-logs.txt"

tfvars="$REPO_ROOT/terraform/terraform.tfvars"
tf_output="$REPO_ROOT/artifacts/validation/terraform-output.json"

tfvar_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 ~ "^[[:space:]]*" k "[[:space:]]*$" {gsub(/[ \"]/,"",$2); print $2; exit}' "$tfvars"
}

tf_output_value() {
  local key="$1"
  python3 - "$tf_output" "$key" <<'PY'
import json
import sys

path, key = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    value = (json.load(fh).get(key, {}) or {}).get("value")
if value is None:
    print("")
elif isinstance(value, list):
    print(",".join(str(item) for item in value))
else:
    print(value)
PY
}

oci_cli() {
  oci --profile "${OCI_CLI_PROFILE:-$(tfvar_value oci_config_profile)}" --region "${OCI_REGION:-$(tfvar_value region)}" "$@"
}

compartment_id="$(tfvar_value compartment_id)"
target_ip="$(tf_output_value ubuntu_agent_private_ip)"
if [[ -z "$target_ip" ]]; then
  target_ip="$(tf_output_value ol9_agent_private_ip)"
fi
if [[ -z "$compartment_id" || -z "$target_ip" ]]; then
  echo "missing compartment_id or target private IP; run make up first" >&2
  exit 2
fi

read -r before_audit before_flow < <(wazuh_ssh "sudo python3 -c 'from pathlib import Path; text=Path(\"/var/ossec/logs/alerts/alerts.json\").read_text(errors=\"ignore\"); print(text.count(\"\\\"id\\\":\\\"100000\\\"\"), text.count(\"\\\"id\\\":\\\"100100\\\"\"))'")

tag_name="wazuhDemo$(date -u +%Y%m%d%H%M%S)"
tag_namespace_id="$(oci_cli iam tag-namespace create \
  --compartment-id "$compartment_id" \
  --name "$tag_name" \
  --description "temporary Wazuh real OCI Audit validation" \
  --query 'data.id' \
  --raw-output)"

if [[ -n "$tag_namespace_id" && "$tag_namespace_id" != "null" ]]; then
  oci_cli iam tag-namespace delete --tag-namespace-id "$tag_namespace_id" --force >/dev/null 2>&1 || true
fi

wazuh_ssh "set -euo pipefail
timeout 3 bash -c '</dev/tcp/${target_ip}/3389' >/dev/null 2>&1 || true
deadline=\$((SECONDS + ${REAL_OCI_LOG_TIMEOUT_SECONDS:-900}))
while (( SECONDS < deadline )); do
  audit_count=\$(sudo grep -c '\"id\":\"100000\"' /var/ossec/logs/alerts/alerts.json || true)
  flow_count=\$(sudo grep -c '\"id\":\"100100\"' /var/ossec/logs/alerts/alerts.json || true)
  if (( audit_count > ${before_audit:-0} && flow_count > ${before_flow:-0} )); then
    printf 'real_oci_logs=green\naudit_rule_100000=green\nflow_rule_100100=green\n'
    exit 0
  fi
  sleep 30
done
printf 'real_oci_logs=red\naudit_before=%s\naudit_after=%s\nflow_before=%s\nflow_after=%s\n' '${before_audit:-0}' \"\$audit_count\" '${before_flow:-0}' \"\$flow_count\"
exit 1" > "$evidence"

cat "$evidence"
