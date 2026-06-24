#!/usr/bin/env bash
set -euo pipefail

mode="${1:-install}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tfvars="${TFVARS_FILE:-$repo_root/terraform/terraform.tfvars}"
artifacts_dir="$repo_root/artifacts/validation"
inventory_file="$artifacts_dir/goad-wazuh-inventory.ini"
evidence_file="$artifacts_dir/M5-goad-wazuh.txt"
tunnel_pid_file="$artifacts_dir/goad-wazuh-tunnel.pid"
mkdir -p "$artifacts_dir" "$repo_root/.ansible/tmp"

tfvar_value() {
  local key="$1"
  [[ -f "$tfvars" ]] || return 0
  awk -F= -v k="$key" '$1 ~ "^[[:space:]]*" k "[[:space:]]*$" {gsub(/[ \"]/,"",$2); print $2; exit}' "$tfvars"
}

tf_output_value() {
  local key="$1"
  python3 - "$artifacts_dir/terraform-output.json" "$key" <<'PY'
import json
import sys

path, key = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as fh:
        value = (json.load(fh).get(key, {}) or {}).get("value")
except FileNotFoundError:
    value = None
print("" if value is None else value)
PY
}

oci_cli() {
  local profile region
  profile="${OCI_PROFILE:-${OCI_CLI_PROFILE:-$(tfvar_value oci_config_profile)}}"
  region="${OCI_REGION:-$(tfvar_value region)}"
  if [[ -n "$region" ]]; then
    oci --profile "${profile:-DEFAULT}" --region "$region" "$@"
  else
    oci --profile "${profile:-DEFAULT}" "$@"
  fi
}

resolve_ansible_playbook() {
  if command -v ansible-playbook >/dev/null 2>&1; then
    command -v ansible-playbook
    return 0
  fi
  if [[ -x "$HOME/.goad/.venv/bin/ansible-playbook" ]]; then
    printf '%s\n' "$HOME/.goad/.venv/bin/ansible-playbook"
    return 0
  fi
  return 1
}

goad_inventory_path() {
  if [[ -n "${GOAD_INVENTORY:-}" ]]; then
    printf '%s\n' "$GOAD_INVENTORY"
    return 0
  fi
  local base="${GOAD_PATH:-$HOME/dev/GOADv3}"
  for candidate in \
    "$base/ad/GOAD/providers/oci/inventory" \
    "$base/ad/GOAD/data/inventory"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

inventory_var() {
  local inventory="$1"
  local key="$2"
  awk -F= -v k="$key" '$1 ~ "^[[:space:]]*" k "[[:space:]]*$" {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' "$inventory"
}

resolve_ssh_key() {
  if [[ -n "${GOAD_JUMPBOX_SSH_KEY:-}" && -f "$GOAD_JUMPBOX_SSH_KEY" ]]; then
    printf '%s\n' "$GOAD_JUMPBOX_SSH_KEY"
    return 0
  fi
  local base="${GOAD_PATH:-$HOME/dev/GOADv3}"
  for candidate in \
    "$(tfvar_value ssh_private_key_path)" \
    "$base/ad/GOAD/providers/oci/ssh_keys/ubuntu-jumpbox.pem" \
    "$base/template/provider/oci/ssh_keys/ubuntu-jumpbox.pem"; do
    candidate="${candidate/#\~/$HOME}"
    if [[ -n "$candidate" && -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

instance_id_by_name() {
  local name="$1"
  python3 - "$artifacts_dir/M5-goad-discovery-raw.json" "$name" <<'PY'
import json
import sys

path, wanted = sys.argv[1], sys.argv[2].lower()
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
for compartment in data.get("compartments", []):
    for inst in compartment.get("instances", []):
        if (inst.get("display-name") or "").lower() == wanted:
            print(inst["id"])
            raise SystemExit
PY
}

instance_ip() {
  local instance_id="$1"
  local field="$2"
  oci_cli compute instance list-vnics \
    --instance-id "$instance_id" \
    --query "data[0].\"$field\"" \
    --raw-output
}

ensure_discovery() {
  if [[ ! -f "$artifacts_dir/M5-goad-discovery-raw.json" ]]; then
    "$repo_root/scripts/goad-discover.sh" >/dev/null
  fi
}

write_inventory_and_start_tunnel() {
  ensure_discovery

  local source_inventory ssh_key jumpbox_id jumpbox_ip wazuh_ip winrm_user winrm_password
  local tunnel_host tunnel_user tunnel_label
  source_inventory="$(goad_inventory_path)"
  ssh_key="$(resolve_ssh_key)"
  jumpbox_id="$(instance_id_by_name jumpbox)"
  jumpbox_ip="${GOAD_JUMPBOX_PUBLIC_IP:-$(instance_ip "$jumpbox_id" public-ip)}"
  wazuh_ip="${WAZUH_MANAGER_IP:-$(tf_output_value wazuh_private_ip)}"
  tunnel_user="${GOAD_TUNNEL_USER:-ubuntu}"
  tunnel_host="${GOAD_TUNNEL_HOST:-$(tf_output_value wazuh_public_ip)}"
  tunnel_label="wazuh"
  if [[ "${GOAD_TUNNEL_MODE:-wazuh}" == "jumpbox" ]]; then
    tunnel_host="$jumpbox_ip"
    tunnel_label="goad-jumpbox"
  fi
  winrm_user="${GOAD_WINRM_USER:-$(inventory_var "$source_inventory" ansible_user)}"
  winrm_password="${GOAD_WINRM_PASSWORD:-$(inventory_var "$source_inventory" ansible_password)}"

  if [[ -z "$tunnel_host" || "$tunnel_host" == "null" || -z "$wazuh_ip" || -z "$winrm_user" || -z "$winrm_password" ]]; then
    echo "missing tunnel host, Wazuh IP, or WinRM credentials" >&2
    exit 2
  fi

  local -a forwards=()
  local base_port="${GOAD_WINRM_BASE_PORT:-15985}"
  local idx=0
  {
    echo "[goad_hosts]"
    for entry in \
      "kingslanding:dc01" \
      "winterfell:dc02" \
      "castelblack:srv02" \
      "meereen:dc03" \
      "braavos:srv03"; do
      local host alias instance_id private_ip local_port
      host="${entry%%:*}"
      alias="${entry##*:}"
      instance_id="$(instance_id_by_name "$host")"
      private_ip="$(instance_ip "$instance_id" private-ip)"
      local_port=$((base_port + idx))
      forwards+=(-L "${local_port}:${private_ip}:5986")
      printf '%s ansible_host=127.0.0.1 ansible_port=%s goad_alias=%s wazuh_agent_name=%s\n' "$host" "$local_port" "$alias" "$host"
      idx=$((idx + 1))
    done
    cat <<EOF

[goad_hosts:vars]
ansible_user=$winrm_user
ansible_password=$winrm_password
ansible_connection=winrm
ansible_winrm_server_cert_validation=ignore
ansible_winrm_transport=basic
ansible_winrm_scheme=https
ansible_winrm_operation_timeout_sec=500
ansible_winrm_read_timeout_sec=600
wazuh_manager_ip=$wazuh_ip
wazuh_agent_group=goad-windows
EOF
  } > "$inventory_file"
  chmod 0600 "$inventory_file"

  if [[ -f "$tunnel_pid_file" ]] && kill -0 "$(cat "$tunnel_pid_file")" >/dev/null 2>&1; then
    return 0
  fi

  echo "Starting SSH WinRM tunnel via ${tunnel_label} ${tunnel_user}@${tunnel_host} ..."
  ssh -i "$ssh_key" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    "${forwards[@]}" \
    -N "${tunnel_user}@${tunnel_host}" &
  echo "$!" > "$tunnel_pid_file"
  sleep 3
  if ! kill -0 "$(cat "$tunnel_pid_file")" >/dev/null 2>&1; then
    echo "failed to start GOAD WinRM tunnel through jumpbox" >&2
    exit 3
  fi
}

stop_tunnel() {
  if [[ -f "$tunnel_pid_file" ]]; then
    kill "$(cat "$tunnel_pid_file")" >/dev/null 2>&1 || true
    wait "$(cat "$tunnel_pid_file")" 2>/dev/null || true
    rm -f "$tunnel_pid_file"
  fi
}

ansible_env() {
  export ANSIBLE_LOCAL_TEMP="$repo_root/.ansible/tmp"
  export ANSIBLE_REMOTE_TEMP="C:\\Windows\\Temp\\ansible"
  export ANSIBLE_ROLES_PATH="$repo_root/ansible/roles"
  export ANSIBLE_HOST_KEY_CHECKING=False
  export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
}

install_socfortress_rules() {
  source "$repo_root/scripts/wazuh-ssh.sh"
  wazuh_ssh 'set -euo pipefail
sudo /var/ossec/bin/agent_groups -a -g goad-windows -q >/dev/null 2>&1 || true
sudo apt-get update >/dev/null
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git >/dev/null
sudo mkdir -p /opt/socfortress-wazuh-rules /var/ossec/etc/rules/socfortress /var/ossec/etc/decoders/socfortress
if [[ ! -d /opt/socfortress-wazuh-rules/.git ]]; then
  sudo git clone https://github.com/socfortress/Wazuh-Rules.git /opt/socfortress-wazuh-rules
fi
sudo git -C /opt/socfortress-wazuh-rules fetch --all --tags >/dev/null
sudo git -C /opt/socfortress-wazuh-rules checkout 66b70d6a380b2cffb625801da0b0ccb1933ed95d >/dev/null
while IFS= read -r src; do sudo install -o wazuh -g wazuh -m 0640 "$src" "/var/ossec/etc/rules/socfortress/$(basename "$src")"; done < <(find /opt/socfortress-wazuh-rules -type f -path "*/rules/*.xml" | sort)
while IFS= read -r src; do sudo install -o wazuh -g wazuh -m 0640 "$src" "/var/ossec/etc/decoders/socfortress/$(basename "$src")"; done < <(find /opt/socfortress-wazuh-rules -type f -path "*/decoders/*.xml" | sort)
sudo /var/ossec/bin/wazuh-analysisd -t
sudo systemctl restart wazuh-manager
'
}

remove_wazuh_agent_records() {
  source "$repo_root/scripts/wazuh-ssh.sh"
  wazuh_ssh 'set -euo pipefail
for name in kingslanding winterfell castelblack meereen braavos; do
  ids="$(sudo /var/ossec/bin/agent_control -l | awk -v n="$name" '"'"'$0 ~ "Name: " n "([, ]|$)" {gsub(",", "", $2); print $2}'"'"' || true)"
  for id in $ids; do
    sudo /var/ossec/bin/manage_agents -r "$id" >/dev/null 2>&1 || sudo /var/ossec/bin/agent_control -R "$id" >/dev/null 2>&1 || true
  done
done
'
}

run_playbook() {
  local playbook="$1"
  local ansible_playbook
  ansible_playbook="$(resolve_ansible_playbook)"
  ansible_env
  "$ansible_playbook" -i "$inventory_file" "$playbook"
}

validate_agents() {
  source "$repo_root/scripts/wazuh-ssh.sh"
  wazuh_ssh 'sudo /var/ossec/bin/agent_control -l' > "$artifacts_dir/M5-goad-agent-control.txt"
  wazuh_ssh 'sudo grep -E '"'"'"name":"(kingslanding|winterfell|castelblack|meereen|braavos)"'"'"' /var/ossec/logs/alerts/alerts.json | grep -E '"'"'Microsoft-Windows-Sysmon/Operational|"sysmon"|socfortress'"'"' | tail -20' > "$artifacts_dir/M5-goad-sysmon-alerts.txt" || true
  local missing=0
  for host in kingslanding winterfell castelblack meereen braavos; do
    if grep -q "Name: ${host}.*Active" "$artifacts_dir/M5-goad-agent-control.txt"; then
      echo "host.${host}=Active"
    else
      echo "host.${host}=missing"
      missing=1
    fi
  done | tee "$evidence_file"
  if [[ -s "$artifacts_dir/M5-goad-sysmon-alerts.txt" ]]; then
    echo "goad_sysmon_socfortress_alerts=green" | tee -a "$evidence_file"
  else
    echo "goad_sysmon_socfortress_alerts=missing" | tee -a "$evidence_file"
    missing=1
  fi
  return "$missing"
}

case "$mode" in
  install|up)
    write_inventory_and_start_tunnel
    trap stop_tunnel EXIT
    install_socfortress_rules
    run_playbook "$repo_root/ansible/playbooks/agent-windows.yml"
    validate_agents
    ;;
  cleanup|down)
    write_inventory_and_start_tunnel
    trap stop_tunnel EXIT
    run_playbook "$repo_root/ansible/playbooks/goad-cleanup.yml" || true
    remove_wazuh_agent_records || true
    {
      echo "goad_cleanup=attempted"
      echo "wazuh_agent_records=removed"
    } > "$evidence_file"
    cat "$evidence_file"
    ;;
  validate)
    validate_agents
    ;;
  *)
    echo "usage: $0 {install|up|cleanup|down|validate}" >&2
    exit 2
    ;;
esac
