#!/usr/bin/env bash
set -euo pipefail

PROFILE="${OCI_CLI_PROFILE:-cap}"
REGION="${OCI_REGION:-eu-frankfurt-1}"
PROJECT_NAME="${PROJECT_NAME:-oci-wazuh-demo}"
NETWORK_COMPARTMENT_NAME="${NETWORK_COMPARTMENT_NAME:-demo-network}"
OPERATOR_CIDR="${OPERATOR_CIDR:-}"
TFVARS="terraform/terraform.tfvars"
mkdir -p artifacts/validation artifacts/runtime

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

need oci
need terraform

if [[ -z "$OPERATOR_CIDR" || "$OPERATOR_CIDR" == "0.0.0.0/0" || "$OPERATOR_CIDR" == "::/0" ]]; then
  echo "set OPERATOR_CIDR to the restricted operator address range" >&2
  exit 2
fi

tenancy_id="$(awk -v profile="[$PROFILE]" '
  $0 == profile { in_profile=1; next }
  /^\[/ { in_profile=0 }
  in_profile && $1 == "tenancy" {
    value=$0
    sub(/^[^=]*=/, "", value)
    gsub(/[[:space:]]/, "", value)
    print value
    exit
  }
' ~/.oci/config)"

if [[ -z "$tenancy_id" ]]; then
  echo "could not resolve tenancy for OCI profile $PROFILE" >&2
  exit 1
fi

compartment_id="${COMPARTMENT_ID:-}"
if [[ -z "${COMPARTMENT_ID:-}" ]]; then
  compartment_id="$(oci iam compartment list \
    --profile "$PROFILE" \
    --compartment-id "$tenancy_id" \
    --compartment-id-in-subtree true \
    --access-level ACCESSIBLE \
    --all \
    --query "data[?name=='${TARGET_COMPARTMENT_NAME:-demo-cyberrange}' && \"lifecycle-state\"=='ACTIVE'] | [0].id" \
    --raw-output)"
fi
if [[ -z "$compartment_id" || "$compartment_id" == "null" ]]; then
  echo "could not resolve target compartment. Set COMPARTMENT_ID or TARGET_COMPARTMENT_NAME." >&2
  exit 1
fi

ssh_pub="${SSH_PUBLIC_KEY_PATH:-}"
ssh_priv="${SSH_PRIVATE_KEY_PATH:-}"
if [[ -z "$ssh_pub" ]]; then
  for candidate in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
    private_candidate="${candidate%.pub}"
    if [[ -f "$candidate" && -f "$private_candidate" ]]; then
      ssh_pub="$candidate"
      ssh_priv="${ssh_priv:-$private_candidate}"
      break
    fi
  done
fi
if [[ -z "$ssh_priv" ]]; then
  if [[ "$ssh_pub" == *.pub ]]; then
    ssh_priv="${ssh_pub%.pub}"
  else
    ssh_priv="$HOME/.ssh/id_rsa"
  fi
fi

if [[ ! -f "$ssh_pub" ]]; then
  echo "SSH public key not found. Set SSH_PUBLIC_KEY_PATH." >&2
  exit 1
fi
if [[ ! -f "$ssh_priv" ]]; then
  echo "SSH private key not found. Set SSH_PRIVATE_KEY_PATH." >&2
  exit 1
fi

availability_domain="$(oci iam availability-domain list --profile "$PROFILE" --compartment-id "$tenancy_id" --query 'data[0].name' --raw-output)"
ol9_image_id="$(oci compute image list --profile "$PROFILE" --compartment-id "$tenancy_id" --operating-system "Oracle Linux" --operating-system-version 9 --shape VM.Standard.E5.Flex --sort-by TIMECREATED --sort-order DESC --limit 1 --query 'data[0].id' --raw-output)"
ubuntu_image_id="$(oci compute image list --profile "$PROFILE" --compartment-id "$tenancy_id" --operating-system "Canonical Ubuntu" --operating-system-version 24.04 --shape VM.Standard.E5.Flex --sort-by TIMECREATED --sort-order DESC --limit 1 --query 'data[0].id' --raw-output)"
object_storage_namespace="$(oci os ns get --profile "$PROFILE" --query 'data' --raw-output)"
log_analytics_namespace="$(oci log-analytics namespace list --profile "$PROFILE" --compartment-id "$tenancy_id" --query 'data.items[0]."namespace-name"' --raw-output)"
if [[ -z "$object_storage_namespace" || "$object_storage_namespace" == "null" ]]; then
  echo "could not resolve Object Storage namespace for profile $PROFILE" >&2
  exit 1
fi
if [[ -z "$log_analytics_namespace" || "$log_analytics_namespace" == "null" ]]; then
  echo "could not resolve Log Analytics namespace; onboard Log Analytics or disable the bridge" >&2
  exit 1
fi
bastion_subnet_id="${BASTION_SUBNET_ID:-}"
agent_subnet_id="${AGENT_SUBNET_ID:-}"
if [[ -z "$bastion_subnet_id" || -z "$agent_subnet_id" ]]; then
  network_compartment_id="$(oci iam compartment list \
    --profile "$PROFILE" \
    --compartment-id "$tenancy_id" \
    --compartment-id-in-subtree true \
    --access-level ACCESSIBLE \
    --all \
    --query "data[?name=='${NETWORK_COMPARTMENT_NAME}' && \"lifecycle-state\"=='ACTIVE'] | [0].id" \
    --raw-output)"
  if [[ -z "$network_compartment_id" || "$network_compartment_id" == "null" ]]; then
    echo "could not resolve network compartment. Set NETWORK_COMPARTMENT_NAME." >&2
    exit 1
  fi
  if [[ -z "$bastion_subnet_id" ]]; then
    bastion_subnet_id="$(oci network subnet list \
      --profile "$PROFILE" \
      --compartment-id "$network_compartment_id" \
      --all \
      --query "data[?\"display-name\"=='${BASTION_SUBNET_NAME:-demo-hub-public}' && \"lifecycle-state\"=='AVAILABLE'] | [0].id" \
      --raw-output)"
  fi
  if [[ -z "$agent_subnet_id" ]]; then
    agent_subnet_id="$(oci network subnet list \
      --profile "$PROFILE" \
      --compartment-id "$network_compartment_id" \
      --all \
      --query "data[?\"display-name\"=='${TARGET_SUBNET_NAME:-demo-cyberrange-attack}' && \"lifecycle-state\"=='AVAILABLE'] | [0].id" \
      --raw-output)"
  fi
fi
if [[ -z "$bastion_subnet_id" || "$bastion_subnet_id" == "null" || -z "$agent_subnet_id" || "$agent_subnet_id" == "null" ]]; then
  echo "could not resolve deployment subnet. Set BASTION_SUBNET_ID/AGENT_SUBNET_ID or TARGET_SUBNET_NAME." >&2
  exit 1
fi
if [[ "${USE_BASTION_SUBNET_FOR_WORKLOADS:-false}" == "true" ]]; then
  agent_subnet_id="$bastion_subnet_id"
fi

preserved_existing_flow_logs=""
preserved_goad_agent_cidrs=""
if [[ -f "$TFVARS" ]]; then
  preserved_existing_flow_logs="$(awk '
    /^[[:space:]]*existing_flow_logs[[:space:]]*=/ { capture=1 }
    capture { print }
    capture && /^[[:space:]]*][[:space:]]*$/ { exit }
    capture && /^[[:space:]]*}][[:space:]]*$/ { exit }
  ' "$TFVARS")"
  preserved_goad_agent_cidrs="$(awk '
    /^[[:space:]]*goad_agent_cidrs[[:space:]]*=/ { print; exit }
  ' "$TFVARS")"
fi

cat > "$TFVARS" <<EOF
region               = "$REGION"
oci_config_profile   = "$PROFILE"
tenancy_id           = "$tenancy_id"
compartment_id       = "$compartment_id"
project_name         = "$PROJECT_NAME"
network_mode        = "${NETWORK_MODE:-existing}"
availability_domain  = "$availability_domain"
ol9_image_id         = "$ol9_image_id"
ubuntu2404_image_id  = "$ubuntu_image_id"
bastion_subnet_id    = "$bastion_subnet_id"
agent_subnet_id      = "$agent_subnet_id"
workload_assign_public_ip = ${WORKLOAD_ASSIGN_PUBLIC_IP:-false}
operator_cidr        = "$OPERATOR_CIDR"
ssh_public_key_path  = "$ssh_pub"
ssh_private_key_path = "$ssh_priv"
ingestion_mode       = "${INGESTION_MODE:-streaming}"
windows_mode         = "${WINDOWS_MODE:-auto}"
enable_log_analytics_bridge = true
object_storage_namespace = "$object_storage_namespace"
log_analytics_namespace = "$log_analytics_namespace"
EOF

if [[ -n "${EXISTING_FLOW_LOGS_HCL_FILE:-}" ]]; then
  cat "$EXISTING_FLOW_LOGS_HCL_FILE" >> "$TFVARS"
elif [[ -n "$preserved_existing_flow_logs" ]]; then
  printf '\n%s\n' "$preserved_existing_flow_logs" >> "$TFVARS"
fi

if [[ -n "${GOAD_AGENT_CIDRS_HCL:-}" ]]; then
  printf '\ngoad_agent_cidrs = %s\n' "$GOAD_AGENT_CIDRS_HCL" >> "$TFVARS"
elif [[ -n "$preserved_goad_agent_cidrs" ]]; then
  printf '\n%s\n' "$preserved_goad_agent_cidrs" >> "$TFVARS"
fi

cat > artifacts/validation/cap-context.txt <<EOF
profile=$PROFILE
region=$REGION
project=$PROJECT_NAME
compartment_configured=true
tfvars=$TFVARS
EOF

export TF_VAR_region="$REGION"
export OCI_CLI_PROFILE="$PROFILE"
export OCI_CONFIG_PROFILE="$PROFILE"

terraform -chdir=terraform init -input=false
terraform -chdir=terraform apply -input=false -auto-approve
terraform -chdir=terraform output -json > artifacts/runtime/terraform-output.json
