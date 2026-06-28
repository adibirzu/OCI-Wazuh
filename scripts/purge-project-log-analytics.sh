#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"
RUNTIME="$ROOT_DIR/artifacts/runtime"
VALIDATION="$ROOT_DIR/artifacts/validation"
project="${1:?project name required}"
profile="${2:-DEFAULT}"
mkdir -p "$RUNTIME" "$VALIDATION"

state_json="$RUNTIME/log-analytics-teardown-state.json"
terraform -chdir="$TF_DIR" show -json terraform.tfstate > "$state_json"
resource_filter='.values.root_module.resources[]? | select(.address == "oci_log_analytics_log_analytics_log_group.wazuh[0]")'
group_count="$(jq "[$resource_filter] | length" "$state_json")"
if [[ "$group_count" -eq 0 ]]; then
  echo "log_analytics_purge=skipped reason=not_in_state"
  exit 0
fi

owned="$(jq -r --arg project "$project" "$resource_filter | .values.freeform_tags.project == \$project" "$state_json")"
[[ "$owned" == "true" ]] || {
  echo "log_analytics_purge=blocked reason=ownership_mismatch" >&2
  exit 6
}

group_id="$(jq -r "$resource_filter | .values.id" "$state_json")"
compartment_id="$(jq -r "$resource_filter | .values.compartment_id" "$state_json")"
namespace="$(jq -r "$resource_filter | .values.namespace" "$state_json")"
end_time="$(python3 -c 'from datetime import datetime, timedelta, timezone; print((datetime.now(timezone.utc) + timedelta(days=1)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
query="logGroupId:\"$group_id\""
profile_args=(--profile "$profile")

estimate_file="$RUNTIME/log-analytics-purge-estimate.json"
oci "${profile_args[@]}" log-analytics storage estimate-purge-data-size \
  --compartment-id "$compartment_id" \
  --namespace-name "$namespace" \
  --time-data-ended "$end_time" \
  --data-type LOG \
  --purge-query-string "$query" > "$estimate_file"
purge_bytes="$(jq -r '.data."purge-data-size-in-bytes" // 0' "$estimate_file")"

status="SKIPPED_EMPTY"
if [[ "$purge_bytes" -gt 0 ]]; then
  submit_file="$RUNTIME/log-analytics-purge-submit.json"
  oci "${profile_args[@]}" log-analytics storage purge-storage-data \
    --compartment-id "$compartment_id" \
    --namespace-name "$namespace" \
    --time-data-ended "$end_time" \
    --data-type LOG \
    --purge-query-string "$query" > "$submit_file"
  work_request_id="$(jq -r '."opc-work-request-id"' "$submit_file")"
  status="IN_PROGRESS"
  for _poll_attempt in $(seq 1 40); do
    status_file="$RUNTIME/log-analytics-purge-status.json"
    oci "${profile_args[@]}" log-analytics storage get-storage-work-request \
      --namespace-name "$namespace" \
      --work-request-id "$work_request_id" > "$status_file"
    status="$(jq -r '.data.status' "$status_file")"
    [[ "$status" == "SUCCEEDED" || "$status" == "FAILED" ]] && break
    sleep 15
  done
  [[ "$status" == "SUCCEEDED" ]] || {
    echo "log_analytics_purge=failed status=$status" >&2
    exit 7
  }
fi

jq -n \
  --arg project "$project" \
  --arg state "$status" \
  --argjson purge_bytes "$purge_bytes" \
  '{gate:"log-analytics-purge",project_name:$project,purge_bytes:$purge_bytes,state:$state}' \
  > "$VALIDATION/log-analytics-purge.json"
echo "log_analytics_purge=green bytes=$purge_bytes"
