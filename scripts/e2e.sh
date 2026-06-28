#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

mode="${E2E_MODE:-local-bastion}"
if [[ "${M11_RUN_INITIALIZED:-false}" != "true" ]]; then
  bash scripts/validation-run.sh --directory artifacts/validation --mode "$mode" --run-id "${VALIDATION_RUN_ID:-}"
fi

if [[ "${1:-}" == "--dry-run" ]]; then
  python3 - <<'PY'
import json
from pathlib import Path
from m11.artifacts import write_gate

directory = Path("artifacts/validation")
context = json.loads((directory / "_run.json").read_text(encoding="utf-8"))
write_gate(directory, context, "e2e-dry-run", "skipped", {"reason": "dry-run"})
PY
  exit 0
fi

outputs="artifacts/runtime/terraform-output.json"
if [[ ! -s "$outputs" ]]; then
  echo "missing $outputs; run make up first" >&2
  exit 2
fi

ssh_key="${SSH_PRIVATE_KEY_PATH:-}"
if [[ -z "$ssh_key" && -f terraform/terraform.tfvars ]]; then
  ssh_key="$(awk -F= '/ssh_private_key_path/{gsub(/[ "]/ ,"",$2); print $2; exit}' terraform/terraform.tfvars)"
fi
if [[ -z "$ssh_key" || ! -r "${ssh_key/#\~/$HOME}" ]]; then
  echo "set SSH_PRIVATE_KEY_PATH to the private key matching the deployed public key" >&2
  exit 2
fi
ssh_key="${ssh_key/#\~/$HOME}"

read_output() {
  python3 - "$outputs" "$1" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
value = payload[sys.argv[2]]["value"]
print(value if value is not None else "")
PY
}

bastion="$(read_output bastion_public_ip)"
wazuh="$(read_output wazuh_private_ip)"
ssh_last_error="$(mktemp "${TMPDIR:-/tmp}/oci-wazuh-ssh-error.XXXXXX")"
ssh_ctrl_dir="$(mktemp -d "${TMPDIR:-/tmp}/oci-wazuh-ssh.XXXXXX")"
bastion_ctrl="${ssh_ctrl_dir}/bastion"
bastion_user=""
wazuh_user=""

cleanup() {
  if [[ -n "$bastion_user" && -S "$bastion_ctrl" ]]; then
    ssh -S "$bastion_ctrl" -O exit "${bastion_user}@${bastion}" >/dev/null 2>&1 || true
  fi
  rm -f "$ssh_last_error"
  rm -rf "$ssh_ctrl_dir"
}
trap cleanup EXIT

ssh_opts=(
  -o BatchMode=yes
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o GlobalKnownHostsFile=/dev/null
  -o ConnectTimeout=15
  -o ConnectionAttempts=1
  -o ServerAliveInterval=10
  -o ServerAliveCountMax=6
  -i "$ssh_key"
)

try_bastion_user() {
  local user="$1"
  ssh "${ssh_opts[@]}" "${user}@${bastion}" "echo ok" >"$ssh_last_error" 2>&1
}

for attempt in $(seq 1 40); do
  for candidate_user in ubuntu opc; do
    if try_bastion_user "$candidate_user"; then
      bastion_user="$candidate_user"
      break 2
    fi
  done
  echo "waiting for bastion SSH ($attempt/40)" >&2
  sleep 15
done
if [[ -z "$bastion_user" ]]; then
  echo "bastion-only validation failed; direct public Wazuh access is forbidden" >&2
  tail -20 "$ssh_last_error" | sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<REDACTED_IP>/g' >&2
  exit 3
fi

ssh "${ssh_opts[@]}" -M -N -f -o "ControlPath=${bastion_ctrl}" -o ControlPersist=600 \
  "${bastion_user}@${bastion}" >"$ssh_last_error" 2>&1

proxy_cmd="ssh -S ${bastion_ctrl} -o ControlMaster=no -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ${bastion_user}@${bastion}"

run_wazuh() {
  local user="$1"
  local command="$2"
  ssh "${ssh_opts[@]}" -o "ProxyCommand=${proxy_cmd}" "${user}@${wazuh}" "$command"
}

for attempt in $(seq 1 40); do
  for candidate_user in ubuntu opc; do
    if run_wazuh "$candidate_user" "test -f /var/log/cloud-init-output.log" >"$ssh_last_error" 2>&1; then
      wazuh_user="$candidate_user"
      break 2
    fi
  done
  echo "waiting for private Wazuh SSH through bastion ($attempt/40)" >&2
  sleep 15
done
if [[ -z "$wazuh_user" ]]; then
  tail -20 "$ssh_last_error" | sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<REDACTED_IP>/g' >&2
  exit 4
fi

if ! run_wazuh "$wazuh_user" "sudo cloud-init status --wait >/dev/null 2>&1"; then
  echo "wazuh_bootstrap=failed" >&2
  run_wazuh "$wazuh_user" "sudo cloud-init status --long; if sudo test -f /var/log/oci-wazuh-demo/wazuh-install.log; then sudo grep -E -i 'error|failed|could not|unsupported|unable' /var/log/oci-wazuh-demo/wazuh-install.log | tail -80; sudo tail -120 /var/log/oci-wazuh-demo/wazuh-install.log | sed -E '/password|secret|token|credential/Id'; fi" >&2 || true
  exit 7
fi

ready_cmd='sudo /var/ossec/bin/wazuh-control status >/tmp/wazuh.ready && grep -q "wazuh-remoted is running" /tmp/wazuh.ready && grep -q "wazuh-authd is running" /tmp/wazuh.ready && grep -q "wazuh-apid is running" /tmp/wazuh.ready && curl -ksSf -o /dev/null https://127.0.0.1:443'
for attempt in $(seq 1 60); do
  if run_wazuh "$wazuh_user" "$ready_cmd" >"$ssh_last_error" 2>&1; then
    break
  fi
  if [[ "$attempt" -eq 60 ]]; then
    run_wazuh "$wazuh_user" "cloud-init status --long; sudo tail -120 /var/log/cloud-init-output.log" >&2 || true
    exit 7
  fi
  echo "waiting for Wazuh services and dashboard ($attempt/60)" >&2
  sleep 20
done

context_values="$(python3 - <<'PY'
import json
p=json.load(open('artifacts/validation/_run.json', encoding='utf-8'))
print(p['run_id'], p['timestamp'], p['mode'])
PY
)"
read -r run_id timestamp validation_mode <<<"$context_values"

write_header() {
  local gate="$1"
  local state="$2"
  printf 'gate=%s\nrun_id=%s\ntimestamp=%s\nmode=%s\nstate=%s\n' \
    "$gate" "$run_id" "$timestamp" "$validation_mode" "$state"
}

# The single-quoted command is intentionally expanded only on the remote host.
# shellcheck disable=SC2016
api_check='set -euo pipefail; archive=/opt/oci-wazuh-demo/wazuh-install-files.tar; test -f "$archive" || archive=/wazuh-install-files.tar; password=$(sudo tar -xOf "$archive" wazuh-install-files/wazuh-passwords.txt | awk '\''/api_username: .wazuh-wui./{seen=1} seen && /api_password:/{print $2; exit}'\''); test -n "$password"; token=$(curl -ksSf -u "wazuh-wui:$password" -X POST "https://127.0.0.1:55000/security/user/authenticate?raw=true"); test -n "$token"; curl -ksSf -H "Authorization: Bearer $token" "https://127.0.0.1:55000/agents?limit=1" >/dev/null; unset password token; echo api_auth=green'
{
  write_header manager-api green
  run_wazuh "$wazuh_user" "sudo /var/ossec/bin/wazuh-control status"
  run_wazuh "$wazuh_user" "$api_check"
  echo dashboard=reachable-through-bastion
} >artifacts/validation/M3-manager-api.txt

# shellcheck disable=SC2016
views_check='set -euo pipefail; archive=/opt/oci-wazuh-demo/wazuh-install-files.tar; test -f "$archive" || archive=/wazuh-install-files.tar; password=$(sudo tar -xOf "$archive" wazuh-install-files/wazuh-passwords.txt | awk '\''/indexer_username: .admin./{seen=1} seen && /indexer_password:/{print $2; exit}'\''); test -n "$password"; for identifier in wazuh-alerts- oci-audit- oci-flow-; do curl -ksSf --user "admin:$password" --header "osd-xsrf: true" "https://127.0.0.1:443/api/saved_objects/index-pattern/$identifier" >/dev/null; done; unset password; echo opensearch_views=green'
{
  write_header opensearch-views green
  run_wazuh "$wazuh_user" "$views_check"
} >artifacts/validation/M7-opensearch-views.txt

{
  write_header linux-agents green
  run_wazuh "$wazuh_user" "sudo /var/ossec/bin/agent_control -l"
} | sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<REDACTED_IP>/g' >artifacts/validation/M4-agent-control.txt
grep -q "${PROJECT_NAME:-oci-wazuh-demo}-ol9-agent.*Active" artifacts/validation/M4-agent-control.txt
grep -q "${PROJECT_NAME:-oci-wazuh-demo}-ubuntu-agent.*Active" artifacts/validation/M4-agent-control.txt

run_wazuh "$wazuh_user" "sudo /var/ossec/bin/agent_control -r -u 001; sudo /var/ossec/bin/agent_control -r -u 002"
sleep 90
fim_query="sudo grep '\"location\":\"syscheck\"' /var/ossec/logs/alerts/alerts.json | grep -E '\"name\":\"${PROJECT_NAME:-oci-wazuh-demo}-(ol9|ubuntu)-agent\"' | tail -80"
{
  write_header fim green
  run_wazuh "$wazuh_user" "$fim_query" | sed -E \
    -e 's/ocid1[[:alnum:]._-]+/<OCI_OCID>/g' \
    -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<REDACTED_IP>/g'
} >artifacts/validation/M4-fim-alerts.txt
grep -q "${PROJECT_NAME:-oci-wazuh-demo}-ol9-agent" artifacts/validation/M4-fim-alerts.txt
grep -q "${PROJECT_NAME:-oci-wazuh-demo}-ubuntu-agent" artifacts/validation/M4-fim-alerts.txt

python3 - <<'PY'
import json
from pathlib import Path
from m11.artifacts import write_gate

directory = Path("artifacts/validation")
context = json.loads((directory / "_run.json").read_text(encoding="utf-8"))
write_gate(directory, context, "manager", "green", {"access": "bastion", "api_auth": "green"})
write_gate(directory, context, "linux", "green", {"active_agents": 2})
write_gate(directory, context, "fim", "green", {"agents_with_alerts": 2})
write_gate(directory, context, "opensearch-views", "green", {"data_views": 3})
PY

echo "e2e=green mode=bastion"
