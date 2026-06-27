#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p artifacts/validation

tfvars="${TFVARS_FILE:-terraform/terraform.tfvars}"
profile="${OCI_PROFILE:-}"
compartment_id="${COMPARTMENT_OCID:-}"
namespace="${LA_NAMESPACE:-}"
project_name="${PROJECT_NAME:-}"
window_minutes="${LA_FRESHNESS_WINDOW_MINUTES:-60}"
evidence="artifacts/validation/M8-log-analytics-freshness.txt"

tfvar_value() {
  local key="$1"
  [[ -f "$tfvars" ]] || return 0
  awk -F= -v k="$key" '$1 ~ "^[[:space:]]*" k "[[:space:]]*$" {gsub(/[ \"]/,"",$2); print $2; exit}' "$tfvars"
}

trim_value() {
  local value="${1:-}"
  value="${value#\'}"
  value="${value%\'}"
  value="${value#\"}"
  value="${value%\"}"
  printf '%s' "$value"
}

utc_time_minus_minutes() {
  python3 - "$1" <<'PY'
from datetime import datetime, timedelta, timezone
import sys

minutes = int(sys.argv[1])
print((datetime.now(timezone.utc) - timedelta(minutes=minutes)).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
}

utc_now() {
  python3 - <<'PY'
from datetime import datetime, timezone
print(datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
}

numeric_or_zero() {
  local value
  value="$(trim_value "${1:-0}")"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s' "$value"
  else
    printf '0'
  fi
}

if [[ -z "$profile" ]]; then
  profile="$(tfvar_value oci_config_profile)"
fi
profile="${profile:-DEFAULT}"

if [[ -z "$compartment_id" ]]; then
  compartment_id="$(tfvar_value compartment_ocid)"
  compartment_id="${compartment_id:-$(tfvar_value compartment_id)}"
fi
if [[ -z "$compartment_id" || "$compartment_id" == "<COMPARTMENT_OCID>" ]]; then
  echo "missing compartment_id; set COMPARTMENT_OCID or terraform/terraform.tfvars" >&2
  exit 2
fi

if [[ -z "$project_name" ]]; then
  project_name="$(tfvar_value project_name)"
fi
project_name="${project_name:-oci-wazuh-demo}"

if [[ -z "$namespace" ]]; then
  if [[ -s artifacts/runtime/terraform-output.json ]]; then
    namespace="$(python3 - <<'PY'
import json
payload = json.load(open("artifacts/runtime/terraform-output.json", encoding="utf-8"))
print((payload.get("log_analytics_namespace") or {}).get("value") or "")
PY
    )"
  fi
fi
if [[ -z "$namespace" ]]; then
  echo "missing Log Analytics namespace; set LA_NAMESPACE or use Terraform output" >&2
  exit 2
fi

start_time="$(utc_time_minus_minutes "$window_minutes")"
end_time="$(utc_now)"
log_group_name="${project_name}-wazuh-logs"
custom_log_name="${project_name}-wazuh-alerts"
windows_log_name="${project_name}-windows-events"
windows_mode="$(python3 - <<'PY'
import json
payload = json.load(open("artifacts/runtime/terraform-output.json", encoding="utf-8"))
print(payload["effective_modes"]["value"]["windows_mode"])
PY
)"
windows_selected=false
[[ "$windows_mode" != "skip" ]] && windows_selected=true

log_group_id="$(oci --profile "$profile" logging log-group list \
  --compartment-id "$compartment_id" \
  --display-name "$log_group_name" \
  --query 'data[0].id' \
  --raw-output 2>/dev/null || true)"
log_group_id="$(trim_value "$log_group_id")"

custom_log_id=""
windows_log_id=""
if [[ -n "$log_group_id" && "$log_group_id" != "null" && "$log_group_id" != "None" ]]; then
  custom_log_id="$(oci --profile "$profile" logging log list \
    --log-group-id "$log_group_id" \
    --display-name "$custom_log_name" \
    --query 'data[0].id' \
    --raw-output 2>/dev/null || true)"
  custom_log_id="$(trim_value "$custom_log_id")"
  if [[ "$windows_selected" == true ]]; then
    windows_log_id="$(oci --profile "$profile" logging log list \
      --log-group-id "$log_group_id" \
      --display-name "$windows_log_name" \
      --query 'data[0].id' \
      --raw-output 2>/dev/null || true)"
    windows_log_id="$(trim_value "$windows_log_id")"
  fi
fi

logging_count() {
  local log_id="$1"
  if [[ -z "$log_id" || "$log_id" == "null" || "$log_id" == "None" ]]; then
    echo 0
    return
  fi
  oci --profile "$profile" logging-search search-logs \
    --time-start "$start_time" \
    --time-end "$end_time" \
    --search-query "search \"${compartment_id}/${log_group_id}/${log_id}\" | sort by datetime desc" \
    --limit 5 \
    --query 'length(data.results)' \
    --raw-output 2>/dev/null || echo 0
}

log_analytics_count() {
  local query_string="$1"
  local field="$2"
  oci --profile "$profile" log-analytics query search \
  --namespace-name "$namespace" \
  --compartment-id "$compartment_id" \
  --sub-system LOG \
  --query-string "$query_string" \
  --time-start "$start_time" \
  --time-end "$end_time" \
  --query-timeout-in-seconds 45 \
  --should-include-columns true \
  --should-include-total-count true \
  --limit 10 \
  --query "data.items[0].${field}" \
  --raw-output 2>/dev/null || echo 0
}

wazuh_la_query="'Log Source' = 'OCI Unified Schema Logs' and wazuh-alerts-json | stats count as WazuhAlerts"
windows_la_query="'Log Source' = 'OCI Unified Schema Logs' and Channel = 'Microsoft-Windows-Sysmon/Operational' | stats count as WindowsEvents"
logging_recent_count=0
wazuh_la_count=0
windows_logging_count=0
windows_la_count=0
for attempt in $(seq 1 30); do
  logging_recent_count="$(numeric_or_zero "$(logging_count "$custom_log_id")")"
  wazuh_la_count="$(numeric_or_zero "$(log_analytics_count "$wazuh_la_query" WazuhAlerts)")"
  if [[ "$windows_selected" == true ]]; then
    windows_logging_count="$(numeric_or_zero "$(logging_count "$windows_log_id")")"
    windows_la_count="$(numeric_or_zero "$(log_analytics_count "$windows_la_query" WindowsEvents)")"
  fi
  if [[ "$logging_recent_count" -gt 0 && "$wazuh_la_count" -gt 0 ]] && {
    [[ "$windows_selected" == false ]] || [[ "$windows_logging_count" -gt 0 && "$windows_la_count" -gt 0 ]]
  }; then
    break
  fi
  echo "waiting for fresh OCI Logging and Log Analytics records ($attempt/30)" >&2
  sleep 30
done

windows_logging_state=skipped
windows_la_state=skipped
if [[ "$windows_selected" == true ]]; then
  if [[ "$windows_logging_count" -gt 0 ]]; then
    windows_logging_state=ready
  else
    windows_logging_state=missing
  fi
  if [[ "$windows_la_count" -gt 0 ]]; then
    windows_la_state=ready
  else
    windows_la_state=missing
  fi
fi

{
  echo "log_analytics_freshness=started"
  echo "window_minutes=$window_minutes"
  echo "wazuh_alerts_oci_logging_last_window=$([[ "$logging_recent_count" -gt 0 ]] && echo ready || echo missing)"
  echo "wazuh_alerts_oci_logging_count=$logging_recent_count"
  echo "wazuh_alerts_log_analytics_last_window=$([[ "$wazuh_la_count" -gt 0 ]] && echo ready || echo missing)"
  echo "wazuh_alerts_log_analytics_count=$wazuh_la_count"
  echo "wazuh_alerts_log_analytics_source=OCI Unified Schema Logs"
  echo "wazuh_alerts_log_analytics_filter=wazuh-alerts-json"
  echo "windows_events_selected=$windows_selected"
  echo "windows_events_oci_logging_last_window=$windows_logging_state"
  echo "windows_events_oci_logging_count=$windows_logging_count"
  echo "windows_events_log_analytics_last_window=$windows_la_state"
  echo "windows_events_log_analytics_count=$windows_la_count"
} > "$evidence"

cat "$evidence"

if [[ "$logging_recent_count" -le 0 || "$wazuh_la_count" -le 0 ]] || {
  [[ "$windows_selected" == true ]] && [[ "$windows_logging_count" -le 0 || "$windows_la_count" -le 0 ]]
}; then
  exit 5
fi
