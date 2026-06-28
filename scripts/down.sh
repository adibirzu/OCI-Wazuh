#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"
ARTIFACTS="$ROOT_DIR/artifacts/validation"
RUNTIME="$ROOT_DIR/artifacts/runtime"
TFVARS="${TFVARS_FILE:-$TF_DIR/terraform.tfvars}"
mkdir -p "$ARTIFACTS" "$RUNTIME"

tfvar_value() {
  local key="$1"
  [[ -f "$TFVARS" ]] || return 0
  awk -F= -v k="$key" '$1 ~ "^[[:space:]]*" k "[[:space:]]*$" {gsub(/[ \"]/,"",$2); print $2; exit}' "$TFVARS"
}

project_name="${PROJECT_NAME:-$(tfvar_value project_name)}"
project_name="${project_name:-oci-wazuh-demo}"
windows_mode="${WINDOWS_MODE:-$(tfvar_value windows_mode)}"
windows_mode="${windows_mode:-skip}"
reuse_goad_action="${REUSE_GOAD_ACTION:-$(tfvar_value reuse_goad_action)}"
reuse_goad_action="${reuse_goad_action:-install}"
destroy_plan="$RUNTIME/destroy.tfplan"
destroy_json="$RUNTIME/destroy-plan.json"

echo "down_project=$project_name"
echo "windows_mode=$windows_mode"

if [[ "$windows_mode" == "reuse_goad" ]]; then
  if [[ "$reuse_goad_action" != "cleanup" ]]; then
    cat >&2 <<EOF
Refusing destroy for reuse_goad while reuse_goad_action is '$reuse_goad_action'.
Run an apply with reuse_goad_action=cleanup, validate all project ownership
markers are removed, then rerun destroy with the same cleanup input.
EOF
    exit 3
  fi
  bash "$ROOT_DIR/scripts/validate-windows-mode.sh"
  echo "goad_cleanup=verified"
elif [[ "$windows_mode" == "skip" ]]; then
  echo "windows_cleanup=skipped_by_mode"
else
  echo "windows_cleanup=terraform_owned_instances"
fi

profile="${OCI_PROFILE:-${OCI_CLI_PROFILE:-$(tfvar_value oci_config_profile)}}"
profile="${profile:-DEFAULT}"
terraform -chdir="$TF_DIR" init -input=false
bash "$ROOT_DIR/scripts/purge-project-log-analytics.sh" "$project_name" "$profile"
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

destroy_succeeded=false
for destroy_attempt in $(seq 1 4); do
  if [[ "$destroy_attempt" -gt 1 ]]; then
    terraform -chdir="$TF_DIR" plan -destroy -out="$destroy_plan"
    terraform -chdir="$TF_DIR" show -json "$destroy_plan" > "$destroy_json"
    python3 "$ROOT_DIR/scripts/guard-destroy-plan.py" "$destroy_json" "$project_name"
  fi
  if terraform -chdir="$TF_DIR" apply "$destroy_plan"; then
    destroy_succeeded=true
    break
  fi
  if [[ "$destroy_attempt" -lt 4 ]]; then
    echo "destroy_retry=$destroy_attempt/4 waiting_for_oci_consistency" >&2
    sleep 45
  fi
done
[[ "$destroy_succeeded" == "true" ]] || {
  echo "destroy=failed retries_exhausted" >&2
  exit 5
}

residual_count=1
for attempt in $(seq 1 12); do
  residual_count="$(oci --profile "$profile" search resource structured-search \
    --query-text "query all resources where (freeformTags.key = 'project' && freeformTags.value = '$project_name')" \
    --query 'length(data.items)' --raw-output)"
  if [[ "$residual_count" -eq 0 ]]; then
    break
  fi
  echo "waiting for OCI search index to report zero project resources ($attempt/12)" >&2
  sleep 10
done

python3 - "$ARTIFACTS" "$project_name" "$residual_count" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

directory, project, residual = Path(sys.argv[1]), sys.argv[2], int(sys.argv[3])
context_path = directory / "_run.json"
context = json.loads(context_path.read_text(encoding="utf-8")) if context_path.is_file() else {
    "mode": "teardown",
    "run_id": "standalone-teardown",
    "timestamp": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
}
payload = {
    "gate": "destroy-residual",
    "mode": context["mode"],
    "project_name": project,
    "residual_count": residual,
    "run_id": context["run_id"],
    "state": "green" if residual == 0 else "failed",
    "timestamp": context["timestamp"],
}
(directory / "destroy-residual.json").write_text(
    json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
PY

if [[ "$residual_count" -ne 0 ]]; then
  echo "destroy=failed residual_count=$residual_count" >&2
  exit 5
fi
echo "destroy=complete residual_count=0"
