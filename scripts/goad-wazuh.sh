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
  python3 - "$repo_root/artifacts/runtime/terraform-output.json" "$key" <<'PY'
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
  local candidate
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

resolve_jumpbox_metadata_key() {
  local jumpbox_id authorized wanted pub private
  jumpbox_id="$(instance_id_by_name jumpbox 2>/dev/null || true)"
  [[ -n "$jumpbox_id" ]] || return 1
  authorized="$(oci_cli compute instance get \
    --instance-id "$jumpbox_id" \
    --query 'data.metadata."ssh_authorized_keys"' \
    --raw-output 2>/dev/null || true)"
  wanted="$(printf '%s\n' "$authorized" | awk 'NF >= 2 {print $2; exit}')"
  [[ -n "$wanted" && "$wanted" != "null" ]] || return 1
  for pub in "$HOME"/.ssh/*.pub; do
    [[ -f "$pub" ]] || continue
    if awk -v wanted="$wanted" 'NF >= 2 && $2 == wanted {found=1} END {exit found ? 0 : 1}' "$pub"; then
      private="${pub%.pub}"
      if [[ -f "$private" ]]; then
        printf '%s\n' "$private"
        return 0
      fi
    fi
  done
  return 1
}

key_matches_jumpbox_metadata() {
  local private="$1" jumpbox_id authorized wanted derived
  [[ -f "$private" && ! -L "$private" ]] || return 1
  jumpbox_id="$(instance_id_by_name jumpbox 2>/dev/null || true)"
  [[ -n "$jumpbox_id" ]] || return 1
  authorized="$(oci_cli compute instance get \
    --instance-id "$jumpbox_id" \
    --query 'data.metadata."ssh_authorized_keys"' \
    --raw-output 2>/dev/null || true)"
  wanted="$(printf '%s\n' "$authorized" | awk 'NF >= 2 {print $1 " " $2; exit}')"
  derived="$(ssh-keygen -y -f "$private" 2>/dev/null | awk 'NF >= 2 {print $1 " " $2; exit}')"
  [[ -n "$wanted" && "$wanted" != "null" && "$derived" == "$wanted" ]]
}

resolve_goad_workspace() {
  local base="$1" workspace="" candidate=""
  if [[ -n "${GOAD_WORKSPACE_PATH:-}" ]]; then
    workspace="${GOAD_WORKSPACE_PATH/#\~/$HOME}"
    [[ -d "$workspace" ]] || return 1
    printf '%s\n' "$workspace"
    return 0
  fi
  if [[ -n "${GOAD_INSTANCE_ID:-}" ]]; then
    [[ "$GOAD_INSTANCE_ID" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
    workspace="$base/workspace/$GOAD_INSTANCE_ID"
    [[ -d "$workspace" ]] || return 1
    printf '%s\n' "$workspace"
    return 0
  fi
  local -a workspaces=()
  for candidate in "$base"/workspace/*; do
    [[ -d "$candidate" && -f "$candidate/instance.json" ]] && workspaces+=("$candidate")
  done
  [[ "${#workspaces[@]}" -eq 1 ]] || return 1
  printf '%s\n' "${workspaces[0]}"
}

resolve_ssh_key() {
  local purpose="${1:-wazuh}"
  local base="${GOAD_PATH:-$HOME/dev/GOADv3}"
  local workspace="" candidate="" explicit_key=""
  local -a candidates=()
  if [[ "$purpose" == "jumpbox" ]]; then
    explicit_key="${GOAD_JUMPBOX_SSH_KEY:-}"
    explicit_key="${explicit_key/#\~/$HOME}"
    if [[ -n "$explicit_key" ]] && key_matches_jumpbox_metadata "$explicit_key"; then
      printf '%s\n' "$explicit_key"
      return 0
    fi
    if candidate="$(resolve_jumpbox_metadata_key)"; then
      candidates+=("$candidate")
    fi
    if workspace="$(resolve_goad_workspace "$base")"; then
      candidates+=(
        "$workspace/ssh_keys/ubuntu-jumpbox.pem"
        "$workspace/provider/ssh_keys/ubuntu-jumpbox.pem"
      )
    fi
  else
    candidates+=("$(tfvar_value ssh_private_key_path)")
  fi
  for candidate in "${candidates[@]}"; do
    candidate="${candidate/#\~/$HOME}"
    if [[ "$purpose" == "jumpbox" ]] && key_matches_jumpbox_metadata "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    elif [[ "$purpose" != "jumpbox" && -n "$candidate" && -f "$candidate" && ! -L "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  if [[ "$purpose" == "jumpbox" ]]; then
    echo "No unique GOAD workspace key matches deployed jumpbox metadata; set GOAD_INSTANCE_ID or GOAD_WORKSPACE_PATH." >&2
  fi
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

  local source_inventory ssh_key jumpbox_id jumpbox_ip wazuh_ip bastion_ip winrm_user winrm_password
  local bastion_private_ip wazuh_agent_manager_ip
  local tunnel_host tunnel_user tunnel_label tunnel_mode requested_tunnel_mode
  local -a proxy_args=()
  source_inventory="$(goad_inventory_path)"
  jumpbox_id="$(instance_id_by_name jumpbox)"
  jumpbox_ip="${GOAD_JUMPBOX_PUBLIC_IP:-$(instance_ip "$jumpbox_id" public-ip)}"
  wazuh_ip="${WAZUH_MANAGER_IP:-$(tf_output_value wazuh_private_ip)}"
  bastion_ip="$(tf_output_value bastion_public_ip)"
  bastion_private_ip="$(tf_output_value bastion_private_ip)"
  tunnel_user="${GOAD_TUNNEL_USER:-ubuntu}"
  tunnel_host="${GOAD_TUNNEL_HOST:-$(tf_output_value wazuh_public_ip)}"
  requested_tunnel_mode="${GOAD_TUNNEL_MODE:-auto}"
  tunnel_mode="$requested_tunnel_mode"
  if [[ "$requested_tunnel_mode" == "auto" ]]; then
    if [[ -n "$jumpbox_ip" && "$jumpbox_ip" != "null" ]] && resolve_ssh_key jumpbox >/dev/null 2>&1; then
      tunnel_mode="jumpbox"
    else
      tunnel_mode="wazuh"
    fi
  fi
  ssh_key="$(resolve_ssh_key "$tunnel_mode")"
  tunnel_label="wazuh"
  if [[ "$tunnel_mode" == "jumpbox" ]]; then
    tunnel_host="$jumpbox_ip"
    tunnel_label="goad-jumpbox"
  elif [[ -z "$tunnel_host" || "$tunnel_host" == "null" ]]; then
    if [[ -z "$bastion_ip" || "$bastion_ip" == "null" ]]; then
      echo "Wazuh has no public IP and bastion_public_ip is unavailable for ProxyJump" >&2
      exit 2
    fi
    tunnel_host="$wazuh_ip"
    tunnel_label="wazuh-via-bastion"
    proxy_args=(-o "ProxyCommand=ssh -i $ssh_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ${tunnel_user}@${bastion_ip}")
  fi
  winrm_user="${GOAD_WINRM_USER:-$(inventory_var "$source_inventory" ansible_user)}"
  winrm_password="${GOAD_WINRM_PASSWORD:-$(inventory_var "$source_inventory" ansible_password)}"
  wazuh_agent_manager_ip="${GOAD_WAZUH_MANAGER_IP:-$wazuh_ip}"
  if [[ "${GOAD_AGENT_RELAY_MODE:-auto}" != "skip" && "$tunnel_mode" == "jumpbox" && -n "$bastion_private_ip" ]]; then
    wazuh_agent_manager_ip="${GOAD_WAZUH_MANAGER_IP:-$bastion_private_ip}"
  fi

  if [[ -z "$tunnel_host" || "$tunnel_host" == "null" || -z "$wazuh_ip" || -z "$wazuh_agent_manager_ip" || -z "$winrm_user" || -z "$winrm_password" ]]; then
    echo "missing tunnel host, Wazuh IP, or WinRM credentials" >&2
    exit 2
  fi

  local -a forwards=()
  local -a local_ports=()
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
      local_ports+=("$local_port")
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
wazuh_manager_ip=$wazuh_agent_manager_ip
wazuh_agent_group=goad-windows
EOF
  } > "$inventory_file"
  chmod 0600 "$inventory_file"

  if [[ -f "$tunnel_pid_file" ]] && kill -0 "$(cat "$tunnel_pid_file")" >/dev/null 2>&1; then
    return 0
  fi

  local -a ssh_cmd=(
    ssh -i "$ssh_key" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    -n
  )
  if [[ ${#proxy_args[@]} -gt 0 ]]; then
    ssh_cmd+=("${proxy_args[@]}")
  fi
  ssh_cmd+=("${forwards[@]}" -N "${tunnel_user}@${tunnel_host}")

  echo "Starting SSH WinRM tunnel via ${tunnel_label} ${tunnel_user}@${tunnel_host} ..."
  "${ssh_cmd[@]}" &
  echo "$!" > "$tunnel_pid_file"
  for attempt in {1..20}; do
    if ! kill -0 "$(cat "$tunnel_pid_file")" >/dev/null 2>&1; then
      echo "failed to start GOAD WinRM tunnel through ${tunnel_label}" >&2
      exit 3
    fi
    local ready=true
    for local_port in "${local_ports[@]}"; do
      if ! nc -z 127.0.0.1 "$local_port" >/dev/null 2>&1; then
        ready=false
        break
      fi
    done
    if [[ "$ready" == "true" ]]; then
      return 0
    fi
    sleep 2
  done
  echo "GOAD WinRM tunnel started but local forwarded ports did not become ready" >&2
  exit 3
}

configure_bastion_agent_relay() {
  [[ "${GOAD_AGENT_RELAY_MODE:-auto}" != "skip" ]] || return 0
  local bastion_ip wazuh_ip ssh_key
  bastion_ip="$(tf_output_value bastion_public_ip)"
  wazuh_ip="${WAZUH_MANAGER_IP:-$(tf_output_value wazuh_private_ip)}"
  ssh_key="$(tfvar_value ssh_private_key_path)"
  ssh_key="${ssh_key/#\~/$HOME}"
  [[ -n "$bastion_ip" && -n "$wazuh_ip" ]] || return 0
  ssh -i "$ssh_key" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o BatchMode=yes \
    "ubuntu@${bastion_ip}" "WAZUH_IP='${wazuh_ip}' bash -s" <<'REMOTE'
set -euo pipefail
sudo apt-get update >/dev/null
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y socat >/dev/null
for port in 1514 1515; do
  sudo tee "/etc/systemd/system/oci-wazuh-goad-relay-${port}.service" >/dev/null <<EOF
[Unit]
Description=OCI Wazuh GOAD relay ${port}
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:${port},fork,reuseaddr TCP:${WAZUH_IP}:${port}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
done
sudo systemctl daemon-reload
sudo systemctl enable --now oci-wazuh-goad-relay-1514.service oci-wazuh-goad-relay-1515.service
for port in 1514 1515; do
  sudo iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || sudo iptables -I INPUT 5 -p tcp --dport "$port" -j ACCEPT
done
REMOTE
}

remove_bastion_agent_relay() {
  [[ "${GOAD_AGENT_RELAY_MODE:-auto}" != "skip" ]] || return 0
  local bastion_ip ssh_key
  bastion_ip="$(tf_output_value bastion_public_ip)"
  ssh_key="$(tfvar_value ssh_private_key_path)"
  ssh_key="${ssh_key/#\~/$HOME}"
  [[ -n "$bastion_ip" ]] || return 0
  ssh -i "$ssh_key" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o BatchMode=yes \
    "ubuntu@${bastion_ip}" 'sudo systemctl disable --now oci-wazuh-goad-relay-1514.service oci-wazuh-goad-relay-1515.service >/dev/null 2>&1 || true; sudo rm -f /etc/systemd/system/oci-wazuh-goad-relay-1514.service /etc/systemd/system/oci-wazuh-goad-relay-1515.service; for port in 1514 1515; do sudo iptables -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true; done; sudo systemctl daemon-reload' || true
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
    if [[ "${GOAD_PEERING_MODE:-skip}" != "skip" ]]; then
      "$repo_root/scripts/goad-peering.sh" up
    fi
    write_inventory_and_start_tunnel
    trap stop_tunnel EXIT
    configure_bastion_agent_relay
    install_socfortress_rules
    run_playbook "$repo_root/ansible/playbooks/agent-windows.yml"
    validate_agents
    ;;
  cleanup|down)
    write_inventory_and_start_tunnel
    trap stop_tunnel EXIT
    run_playbook "$repo_root/ansible/playbooks/goad-cleanup.yml" || true
    remove_wazuh_agent_records || true
    remove_bastion_agent_relay
    if [[ "${GOAD_PEERING_MODE:-skip}" != "skip" ]]; then
      "$repo_root/scripts/goad-peering.sh" down || true
    fi
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
