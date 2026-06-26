#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"
ARTIFACTS="$ROOT_DIR/artifacts/validation"
TFVARS="${TFVARS_FILE:-$TF_DIR/terraform.tfvars}"
mkdir -p "$ARTIFACTS"

tfvar_value() {
  local key="$1"
  [[ -f "$TFVARS" ]] || return 0
  awk -F= -v k="$key" '$1 ~ "^[[:space:]]*" k "[[:space:]]*$" {gsub(/[ \"]/,"",$2); print $2; exit}' "$TFVARS"
}

project_name="${PROJECT_NAME:-$(tfvar_value project_name)}"
project_name="${project_name:-oci-wazuh-demo}"
windows_mode="${WINDOWS_MODE:-$(tfvar_value windows_mode)}"
windows_mode="${windows_mode:-auto}"
destroy_plan="$ARTIFACTS/destroy.tfplan"
destroy_json="$ARTIFACTS/destroy-plan.json"

echo "down_project=$project_name"
echo "windows_mode=$windows_mode"

if [[ "${SKIP_GOAD_CLEANUP:-false}" == "true" || "$windows_mode" == "skip" ]]; then
  echo "goad_cleanup=skipped"
else
  if bash "$ROOT_DIR/scripts/goad-wazuh.sh" cleanup; then
    echo "goad_cleanup=complete"
  elif [[ "${ALLOW_GOAD_CLEANUP_FAILURE:-false}" == "true" ]]; then
    echo "goad_cleanup=failed_allowed"
  else
    cat >&2 <<EOF
GOAD cleanup failed. Refusing to destroy Wazuh before reused Windows hosts are cleaned.
Set SKIP_GOAD_CLEANUP=true only when no reused GOAD/Windows hosts were modified.
Set ALLOW_GOAD_CLEANUP_FAILURE=true only after manually removing demo agents.
EOF
    exit 3
  fi
fi

terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" plan -destroy -out="$destroy_plan"
terraform -chdir="$TF_DIR" show -json "$destroy_plan" > "$destroy_json"
python3 "$ROOT_DIR/scripts/guard-destroy-plan.py" "$destroy_json" "$project_name"

if [[ "${AUTO_APPROVE:-false}" != "true" && "${DESTROY_CONFIRM:-}" != "$project_name" ]]; then
  cat <<EOF
Destroy plan has passed ownership guard for project '$project_name'.
To continue non-interactively, rerun with:

  DESTROY_CONFIRM=$project_name make down

EOF
  read -r -p "Type '$project_name' to destroy guarded demo resources: " confirmation
  if [[ "$confirmation" != "$project_name" ]]; then
    echo "destroy=cancelled"
    exit 4
  fi
fi

terraform -chdir="$TF_DIR" apply "$destroy_plan"
echo "destroy=complete"
