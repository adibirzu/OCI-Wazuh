#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/validation

tfvars="${TFVARS_FILE:-terraform/terraform.tfvars}"
profile="${OCI_PROFILE:-}"
compartment_id="${COMPARTMENT_OCID:-}"
tenancy_id="${TENANCY_OCID:-}"
project_name="${PROJECT_NAME:-}"
namespace="${LA_NAMESPACE:-}"
evidence="artifacts/validation/M8-wazuh-log-analytics.txt"

tfvar_value() {
  local key="$1"
  [[ -f "$tfvars" ]] || return 0
  awk -F= -v k="$key" '$1 ~ "^[[:space:]]*" k "[[:space:]]*$" {gsub(/[ \"]/,"",$2); print $2}' "$tfvars"
}

trim_quotes() {
  local value="${1:-}"
  value="${value#\'}"
  value="${value%\'}"
  value="${value#\"}"
  value="${value%\"}"
  printf '%s' "$value"
}

oci_cli() {
  oci --profile "$profile" "$@"
}

wait_agent_config() {
  local display_name="$1"
  local waited=0
  while [[ $waited -lt 300 ]]; do
    local state
    state="$(oci_cli logging agent-configuration list \
      --compartment-id "$compartment_id" \
      --display-name "$display_name" \
      --query 'data.items[0]."lifecycle-state"' \
      --raw-output 2>/dev/null || echo "")"
    state="$(trim_quotes "$state")"
    if [[ "$state" == "ACTIVE" ]]; then
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
  return 1
}

resolve_logging_log_group_id() {
  local display_name="$1"
  oci_cli logging log-group list \
    --compartment-id "$compartment_id" \
    --display-name "$display_name" \
    --query 'data[0].id' --raw-output 2>/dev/null || echo ""
}

wait_logging_log_group_id() {
  local display_name="$1"
  local waited=0
  local id=""
  while [[ $waited -lt 180 ]]; do
    id="$(trim_quotes "$(resolve_logging_log_group_id "$display_name")")"
    if [[ -n "$id" && "$id" != "null" && "$id" != "None" ]]; then
      printf '%s' "$id"
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
  return 1
}

resolve_la_log_group_id() {
  local display_name="$1"
  oci_cli log-analytics log-group list \
    --namespace-name "$namespace" \
    --compartment-id "$compartment_id" \
    --display-name "$display_name" \
    --query 'data.items[0].id' --raw-output 2>/dev/null || echo ""
}

wait_la_log_group_id() {
  local display_name="$1"
  local waited=0
  local id=""
  while [[ $waited -lt 180 ]]; do
    id="$(trim_quotes "$(resolve_la_log_group_id "$display_name")")"
    if [[ -n "$id" && "$id" != "null" && "$id" != "None" ]]; then
      printf '%s' "$id"
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
  return 1
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
if [[ -z "$tenancy_id" ]]; then
  tenancy_id="$(tfvar_value tenancy_id)"
fi
if [[ -z "$project_name" ]]; then
  project_name="$(tfvar_value project_name)"
fi
if [[ -z "$project_name" ]]; then
  project_name="oci-wazuh-demo"
fi
if [[ -z "$namespace" ]]; then
  namespace="$(oci_cli os ns get --query data --raw-output)"
fi

if [[ -z "$compartment_id" || "$compartment_id" == "<COMPARTMENT_OCID>" ]]; then
  echo "missing compartment_id; set COMPARTMENT_OCID or terraform/terraform.tfvars" >&2
  exit 2
fi
if [[ -z "$tenancy_id" || "$tenancy_id" == "<TENANCY_OCID>" ]]; then
  echo "missing tenancy_id; set TENANCY_OCID or terraform/terraform.tfvars" >&2
  exit 2
fi

log_group_name="${project_name}-wazuh-logs"
custom_log_name="${project_name}-wazuh-alerts"
agent_config_name="${project_name}-wazuh-alerts"
dynamic_group_name="${project_name}-wazuh-instance"
policy_name="${project_name}-wazuh-log-collection"
sch_name="${project_name}-wazuh-alerts-to-log-analytics"
la_log_group_name="${project_name}-log-analytics"
wazuh_instance_name="${project_name}-wazuh-aio"

log_group_id="$(resolve_logging_log_group_id "$log_group_name")"
log_group_id="$(trim_quotes "$log_group_id")"
if [[ -z "$log_group_id" || "$log_group_id" == "null" || "$log_group_id" == "None" ]]; then
  oci_cli logging log-group create \
    --compartment-id "$compartment_id" \
    --display-name "$log_group_name" \
    --description "Wazuh alert logs for OCI Wazuh demo" >/dev/null
  log_group_id="$(wait_logging_log_group_id "$log_group_name")"
  log_group_id="$(trim_quotes "$log_group_id")"
fi
if [[ -z "$log_group_id" || "$log_group_id" == "null" || "$log_group_id" == "None" ]]; then
  echo "could not resolve OCI Logging log group $log_group_name" >&2
  exit 3
fi

custom_log_id="$(oci_cli logging log list \
  --log-group-id "$log_group_id" \
  --display-name "$custom_log_name" \
  --query 'data[0].id' --raw-output 2>/dev/null || echo "")"
custom_log_id="$(trim_quotes "$custom_log_id")"
if [[ -z "$custom_log_id" || "$custom_log_id" == "null" || "$custom_log_id" == "None" ]]; then
  oci_cli logging log create \
    --log-group-id "$log_group_id" \
    --display-name "$custom_log_name" \
    --log-type CUSTOM >/dev/null
  custom_log_id="$(oci_cli logging log list \
    --log-group-id "$log_group_id" \
    --display-name "$custom_log_name" \
    --query 'data[0].id' --raw-output)"
  custom_log_id="$(trim_quotes "$custom_log_id")"
fi

wazuh_instance_id="$(oci_cli compute instance list \
  --compartment-id "$compartment_id" \
  --display-name "$wazuh_instance_name" \
  --all \
  --query 'data[0].id' --raw-output)"
wazuh_instance_id="$(trim_quotes "$wazuh_instance_id")"
if [[ -z "$wazuh_instance_id" || "$wazuh_instance_id" == "null" || "$wazuh_instance_id" == "None" ]]; then
  echo "could not resolve Wazuh instance by display name $wazuh_instance_name" >&2
  exit 3
fi

dynamic_group_id="$(oci_cli iam dynamic-group list \
  --compartment-id "$tenancy_id" \
  --query "data[?name=='${dynamic_group_name}'].id | [0]" \
  --raw-output 2>/dev/null || echo "")"
dynamic_group_id="$(trim_quotes "$dynamic_group_id")"
matching_rule="ANY {instance.id = '${wazuh_instance_id}'}"
if [[ -z "$dynamic_group_id" || "$dynamic_group_id" == "null" || "$dynamic_group_id" == "None" ]]; then
  dynamic_group_id="$(oci_cli iam dynamic-group create \
    --compartment-id "$tenancy_id" \
    --name "$dynamic_group_name" \
    --description "Wazuh instance for OCI Wazuh alert log collection" \
    --matching-rule "$matching_rule" \
    --query 'data.id' --raw-output)"
  dynamic_group_id="$(trim_quotes "$dynamic_group_id")"
else
  oci_cli iam dynamic-group update \
    --dynamic-group-id "$dynamic_group_id" \
    --matching-rule "$matching_rule" >/dev/null || true
fi

policy_id="$(oci_cli iam policy list \
  --compartment-id "$tenancy_id" \
  --query "data[?name=='${policy_name}'].id | [0]" \
  --raw-output 2>/dev/null || echo "")"
policy_id="$(trim_quotes "$policy_id")"
policy_statements='[
  "Allow dynamic-group '"$dynamic_group_name"' to use log-content in compartment id '"$compartment_id"'",
  "Allow dynamic-group '"$dynamic_group_name"' to read log-groups in compartment id '"$compartment_id"'"
]'
if [[ -z "$policy_id" || "$policy_id" == "null" || "$policy_id" == "None" ]]; then
  oci_cli iam policy create \
    --compartment-id "$tenancy_id" \
    --name "$policy_name" \
    --description "Allow Wazuh instance to publish Wazuh alert logs" \
    --statements "$policy_statements" >/dev/null || true
fi

service_config="$(python3 - "$custom_log_id" <<'PY'
import json
import sys

log_id = sys.argv[1]
print(json.dumps({
    "configurationType": "LOGGING",
    "destination": {"logObjectId": log_id},
    "sources": [{
        "sourceType": "LOG_TAIL",
        "name": "wazuh-alerts-json",
        "paths": ["/var/ossec/logs/alerts/alerts.json"],
        "parser": {
            "parserType": "NONE",
            "isEstimateCurrentEvent": True,
        },
    }],
}))
PY
)"
group_association="$(printf '{"groupList":["%s"]}' "$dynamic_group_id")"

agent_config_id="$(oci_cli logging agent-configuration list \
  --compartment-id "$compartment_id" \
  --display-name "$agent_config_name" \
  --query 'data.items[0].id' --raw-output 2>/dev/null || echo "")"
agent_config_id="$(trim_quotes "$agent_config_id")"
if [[ -z "$agent_config_id" || "$agent_config_id" == "null" || "$agent_config_id" == "None" ]]; then
  oci_cli logging agent-configuration create \
    --compartment-id "$compartment_id" \
    --is-enabled true \
    --display-name "$agent_config_name" \
    --description "Tail Wazuh alerts JSON into OCI Logging" \
    --service-configuration "$service_config" \
    --group-association "$group_association" >/dev/null
else
  oci_cli logging agent-configuration update \
    --config-id "$agent_config_id" \
    --display-name "$agent_config_name" \
    --is-enabled true \
    --service-configuration "$service_config" \
    --group-association "$group_association" \
    --force >/dev/null
fi
wait_agent_config "$agent_config_name" || true

la_log_group_id="$(resolve_la_log_group_id "$la_log_group_name")"
la_log_group_id="$(trim_quotes "$la_log_group_id")"
if [[ -z "$la_log_group_id" || "$la_log_group_id" == "null" || "$la_log_group_id" == "None" ]]; then
  oci_cli log-analytics log-group create \
    --namespace-name "$namespace" \
    --compartment-id "$compartment_id" \
    --display-name "$la_log_group_name" \
    --description "Log Analytics group for OCI Wazuh demo correlations" >/dev/null
  la_log_group_id="$(wait_la_log_group_id "$la_log_group_name")"
  la_log_group_id="$(trim_quotes "$la_log_group_id")"
fi
if [[ -n "$la_log_group_id" && "$la_log_group_id" != "null" && "$la_log_group_id" != "None" ]]; then
  source_json="$(printf '{"kind":"logging","logSources":[{"compartmentId":"%s","logGroupId":"%s"}]}' "$compartment_id" "$log_group_id")"
  target_json="$(printf '{"kind":"loggingAnalytics","logGroupId":"%s"}' "$la_log_group_id")"

  sch_id="$(oci_cli sch service-connector list \
    --compartment-id "$compartment_id" \
    --display-name "$sch_name" \
    --all \
    --query 'data.items[0].id' --raw-output 2>/dev/null || echo "")"
  sch_id="$(trim_quotes "$sch_id")"
  if [[ -z "$sch_id" || "$sch_id" == "null" || "$sch_id" == "None" ]]; then
    oci_cli sch service-connector create \
      --compartment-id "$compartment_id" \
      --display-name "$sch_name" \
      --description "Forward Wazuh alert custom log to Log Analytics" \
      --source "$source_json" \
      --target "$target_json" >/dev/null || true
  else
    oci_cli sch service-connector update \
      --service-connector-id "$sch_id" \
      --source "$source_json" \
      --target "$target_json" \
      --force >/dev/null || true
  fi
fi

{
  echo "wazuh_log_analytics=started"
  echo "oci_logging_log_group=ready"
  echo "oci_logging_custom_log=ready"
  echo "wazuh_dynamic_group=ready"
  echo "wazuh_logging_policy=ready"
  echo "wazuh_agent_config=ready"
  if [[ -n "$la_log_group_id" && "$la_log_group_id" != "null" && "$la_log_group_id" != "None" ]]; then
    echo "sch_to_log_analytics=ready_or_updating"
  else
    echo "sch_to_log_analytics=skipped_missing_log_analytics_log_group"
  fi
} > "$evidence"

cat "$evidence"
