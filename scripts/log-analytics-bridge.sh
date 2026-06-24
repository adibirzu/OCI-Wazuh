#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/validation

tfvars="${TFVARS_FILE:-terraform/terraform.tfvars}"
profile="${OCI_PROFILE:-}"
compartment_id="${COMPARTMENT_OCID:-}"
namespace="${LA_NAMESPACE:-}"
evidence="artifacts/validation/M8-log-analytics-bridge.txt"

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
if [[ -z "$namespace" ]]; then
  namespace="$(oci --profile "$profile" os ns get --query data --raw-output)"
fi

source_count() {
  local source="$1"
  oci --profile "$profile" log-analytics source list-sources \
    --namespace-name "$namespace" \
    --compartment-id "$compartment_id" \
    --source-display-text "$source" \
    --is-system ALL \
    --all \
    --query 'length(data.items)' \
    --raw-output 2>/dev/null || echo 0
}

entity_count() {
  local name="$1"
  oci --profile "$profile" log-analytics entity list \
    --namespace-name "$namespace" \
    --compartment-id "$compartment_id" \
    --name-contains "$name" \
    --lifecycle-state ACTIVE \
    --all \
    --query 'length(data)' \
    --raw-output 2>/dev/null || echo 0
}

required_sources=(
  "Linux Syslog Logs"
  "Linux Secure Logs"
  "Windows Security Events"
  "Windows System Events"
  "Windows Application Events"
  "Windows Sysmon Events"
  "OCI Audit Logs"
  "OCI VCN Flow Unified Schema Logs"
)

required_entities=(
  "oci-wazuh-demo-wazuh-aio"
  "oci-wazuh-demo-ol9-agent"
  "oci-wazuh-demo-ubuntu-agent"
  "braavos"
  "castelblack"
  "kingslanding"
  "meereen"
  "winterfell"
)

{
  echo "log_analytics_bridge=started"
  if oci --profile "$profile" log-analytics namespace get --namespace-name "$namespace" --query 'data."is-onboarded"' --raw-output >/dev/null; then
    echo "namespace=ready"
  else
    echo "namespace=missing"
    exit 3
  fi

  missing=0
  for source in "${required_sources[@]}"; do
    count="$(source_count "$source")"
    if [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]]; then
      echo "source.${source}=ready"
    else
      echo "source.${source}=missing"
      missing=1
    fi
  done

  for entity in "${required_entities[@]}"; do
    count="$(entity_count "$entity")"
    if [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]]; then
      echo "entity.${entity}=ready"
    else
      echo "entity.${entity}=missing"
      missing=1
    fi
  done

  if [[ "$missing" -eq 0 ]]; then
    echo "log_analytics_bridge=ready"
  else
    echo "log_analytics_bridge=partial"
  fi
} > "$evidence"

cat "$evidence"
