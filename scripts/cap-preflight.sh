#!/usr/bin/env bash
set -euo pipefail

PROFILE="${OCI_CLI_PROFILE:-cap}"
TARGET_COMPARTMENT_NAME="${TARGET_COMPARTMENT_NAME:-demo-cyberrange}"
NETWORK_COMPARTMENT_NAME="${NETWORK_COMPARTMENT_NAME:-demo-network}"
TARGET_SUBNET_NAME="${TARGET_SUBNET_NAME:-demo-cyberrange-attack}"
mkdir -p artifacts/validation

profile_value() {
  local key="$1"
  awk -v profile="[$PROFILE]" -v key="$key" '
    $0 == profile { in_profile=1; next }
    /^\[/ { in_profile=0 }
    in_profile && $1 == key {
      value=$0
      sub(/^[^=]*=/, "", value)
      gsub(/[[:space:]]/, "", value)
      print value
      exit
    }
  ' ~/.oci/config
}

tenancy_id="$(profile_value tenancy)"
user_id="$(profile_value user)"

if [[ -z "$tenancy_id" || -z "$user_id" ]]; then
  echo "Could not resolve tenancy/user from OCI profile $PROFILE" >&2
  exit 1
fi

{
  echo "profile=$PROFILE"
  echo "target_compartment_name=$TARGET_COMPARTMENT_NAME"
  echo "network_compartment_name=$NETWORK_COMPARTMENT_NAME"
  echo "target_subnet_name=$TARGET_SUBNET_NAME"
} > artifacts/validation/cap-preflight.txt

oci iam user get --profile "$PROFILE" --user-id "$user_id" \
  --query 'data.{name:name,"lifecycle-state":"lifecycle-state"}' \
  >> artifacts/validation/cap-preflight.txt

oci iam user list-groups --profile "$PROFILE" --user-id "$user_id" \
  --query 'data[].name' \
  >> artifacts/validation/cap-preflight.txt

compartment_id="$(oci iam compartment list \
  --profile "$PROFILE" \
  --compartment-id "$tenancy_id" \
  --compartment-id-in-subtree true \
  --access-level ACCESSIBLE \
  --all \
  --query "data[?name=='$TARGET_COMPARTMENT_NAME' && \"lifecycle-state\"=='ACTIVE'] | [0].id" \
  --raw-output)"

if [[ -z "$compartment_id" || "$compartment_id" == "null" ]]; then
  echo "Target compartment not found/readable: $TARGET_COMPARTMENT_NAME" >&2
  exit 1
fi

network_compartment_id="$(oci iam compartment list \
  --profile "$PROFILE" \
  --compartment-id "$tenancy_id" \
  --compartment-id-in-subtree true \
  --access-level ACCESSIBLE \
  --all \
  --query "data[?name=='$NETWORK_COMPARTMENT_NAME' && \"lifecycle-state\"=='ACTIVE'] | [0].id" \
  --raw-output)"

if [[ -z "$network_compartment_id" || "$network_compartment_id" == "null" ]]; then
  echo "Network compartment not found/readable: $NETWORK_COMPARTMENT_NAME" >&2
  exit 1
fi

subnet_id="$(oci network subnet list \
  --profile "$PROFILE" \
  --compartment-id "$network_compartment_id" \
  --all \
  --query "data[?\"display-name\"=='$TARGET_SUBNET_NAME' && \"lifecycle-state\"=='AVAILABLE'] | [0].id" \
  --raw-output)"

if [[ -z "$subnet_id" || "$subnet_id" == "null" ]]; then
  echo "Target subnet not found/readable: $TARGET_SUBNET_NAME" >&2
  exit 1
fi

echo "target_compartment_resolved=true" >> artifacts/validation/cap-preflight.txt
echo "target_subnet_resolved=true" >> artifacts/validation/cap-preflight.txt

echo "Preflight read checks passed. Run make up to verify create permissions."
