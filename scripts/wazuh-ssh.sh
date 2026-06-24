#!/usr/bin/env bash

wazuh_tf_output_json="${WAZUH_TF_OUTPUT_JSON:-artifacts/validation/terraform-output.json}"
wazuh_tfvars="${TFVARS_FILE:-terraform/terraform.tfvars}"
wazuh_ctrl_dir="${WAZUH_SSH_CONTROL_DIR:-/tmp/ociwssh-${USER:-operator}}"

wazuh_require_outputs() {
  if [[ ! -s "$wazuh_tf_output_json" ]]; then
    echo "missing $wazuh_tf_output_json; run make up first" >&2
    return 2
  fi
}

wazuh_json_output() {
  local key="$1"
  python3 - "$wazuh_tf_output_json" "$key" <<'PY'
import json
import sys

path, key = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
print((data.get(key, {}) or {}).get("value") or "")
PY
}

wazuh_tfvar_value() {
  local key="$1"
  [[ -f "$wazuh_tfvars" ]] || return 0
  awk -F= -v k="$key" '$1 ~ "^[[:space:]]*" k "[[:space:]]*$" {gsub(/[ \"]/,"",$2); print $2}' "$wazuh_tfvars"
}

wazuh_ssh_key() {
  local key
  key="$(wazuh_tfvar_value ssh_private_key_path)"
  if [[ -z "$key" ]]; then
    key="$HOME/.ssh/id_rsa"
  fi
  printf '%s' "$key"
}

wazuh_base_ssh_opts() {
  local key="$1"
  mkdir -p "$wazuh_ctrl_dir"
  chmod 0700 "$wazuh_ctrl_dir" 2>/dev/null || true
  WAZUH_SSH_OPTS=(
    "-o" "BatchMode=yes"
    "-o" "IdentitiesOnly=yes"
    "-o" "StrictHostKeyChecking=no"
    "-o" "UserKnownHostsFile=/dev/null"
    "-o" "GlobalKnownHostsFile=/dev/null"
    "-o" "LogLevel=ERROR"
    "-o" "ConnectTimeout=30"
    "-o" "ConnectionAttempts=1"
    "-o" "ServerAliveInterval=15"
    "-o" "ServerAliveCountMax=2"
    "-i" "$key"
  )
}

wazuh_control_path() {
  local mode="$1"
  local host="$2"
  host="${host//./_}"
  printf '%s/%s-%s' "$wazuh_ctrl_dir" "$mode" "$host"
}

wazuh_ensure_bastion_mux() {
  local key="$1"
  local bastion="$2"
  local ctrl attempt
  local -a opts

  wazuh_base_ssh_opts "$key"
  opts=("${WAZUH_SSH_OPTS[@]}")
  ctrl="$(wazuh_control_path bastion "$bastion")"

  if ssh "${opts[@]}" -o "ControlPath=${ctrl}" -O check "ubuntu@${bastion}" >/dev/null 2>&1; then
    printf '%s' "$ctrl"
    return 0
  fi

  for attempt in 1 2 3; do
    if ssh "${opts[@]}" -M -N -f -o "ControlMaster=yes" -o "ControlPersist=600" -o "ControlPath=${ctrl}" "ubuntu@${bastion}"; then
      printf '%s' "$ctrl"
      return 0
    fi
    [[ "$attempt" -eq 3 ]] && break
    sleep $((attempt * 30))
  done
  return 1
}

wazuh_resolve_target() {
  wazuh_require_outputs
  local key public_ip private_ip bastion_ip
  key="$(wazuh_ssh_key)"
  public_ip="$(wazuh_json_output wazuh_public_ip)"
  private_ip="$(wazuh_json_output wazuh_private_ip)"
  bastion_ip="$(wazuh_json_output bastion_public_ip)"

  if [[ "${WAZUH_SSH_MODE:-auto}" == "bastion" ]]; then
    printf 'bastion|%s|%s|%s\n' "$key" "$private_ip" "$bastion_ip"
  elif [[ -n "$public_ip" ]]; then
    printf 'direct|%s|%s|%s\n' "$key" "$public_ip" ""
  else
    printf 'bastion|%s|%s|%s\n' "$key" "$private_ip" "$bastion_ip"
  fi
}

wazuh_ssh() {
  local command="$1"
  local target mode key host bastion proxy
  target="$(wazuh_resolve_target)"
  IFS='|' read -r mode key host bastion <<<"$target"

  local -a opts
  wazuh_base_ssh_opts "$key"
  opts=("${WAZUH_SSH_OPTS[@]}")

  local ctrl attempt
  ctrl="$(wazuh_control_path "$mode" "$host")"
  if [[ "${WAZUH_SSH_CONTROL:-auto}" != "none" ]]; then
    opts+=("-o" "ControlMaster=auto" "-o" "ControlPersist=600" "-o" "ControlPath=${ctrl}")
  fi

  if [[ "$mode" == "direct" ]]; then
    for attempt in 1 2 3; do
      ssh "${opts[@]}" "ubuntu@${host}" "$command" && return 0
      [[ "$attempt" -eq 3 ]] && break
      sleep $((attempt * 30))
    done
    return 1
  else
    if [[ "${WAZUH_SSH_CONTROL:-auto}" == "none" ]]; then
      proxy="ssh -i ${key} -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ubuntu@${bastion}"
    else
      local bastion_ctrl
      bastion_ctrl="$(wazuh_ensure_bastion_mux "$key" "$bastion")"
      proxy="ssh -S ${bastion_ctrl} -o ControlMaster=no -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ubuntu@${bastion}"
    fi
    for attempt in 1 2 3; do
      ssh "${opts[@]}" -o "ProxyCommand=${proxy}" "ubuntu@${host}" "$command" && return 0
      [[ "$attempt" -eq 3 ]] && break
      sleep $((attempt * 30))
    done
    return 1
  fi
}

wazuh_scp_to() {
  local source="$1"
  local dest="$2"
  local target mode key host bastion proxy
  target="$(wazuh_resolve_target)"
  IFS='|' read -r mode key host bastion <<<"$target"

  local -a opts
  wazuh_base_ssh_opts "$key"
  opts=("${WAZUH_SSH_OPTS[@]}")

  local ctrl attempt
  ctrl="$(wazuh_control_path "$mode" "$host")"
  if [[ "${WAZUH_SSH_CONTROL:-auto}" != "none" ]]; then
    opts+=("-o" "ControlMaster=auto" "-o" "ControlPersist=600" "-o" "ControlPath=${ctrl}")
  fi

  if [[ "$mode" == "direct" ]]; then
    for attempt in 1 2 3; do
      scp "${opts[@]}" "$source" "ubuntu@${host}:${dest}" && return 0
      [[ "$attempt" -eq 3 ]] && break
      sleep $((attempt * 30))
    done
    return 1
  else
    if [[ "${WAZUH_SSH_CONTROL:-auto}" == "none" ]]; then
      proxy="ssh -i ${key} -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ubuntu@${bastion}"
    else
      local bastion_ctrl
      bastion_ctrl="$(wazuh_ensure_bastion_mux "$key" "$bastion")"
      proxy="ssh -S ${bastion_ctrl} -o ControlMaster=no -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ubuntu@${bastion}"
    fi
    for attempt in 1 2 3; do
      scp "${opts[@]}" -o "ProxyCommand=${proxy}" "$source" "ubuntu@${host}:${dest}" && return 0
      [[ "$attempt" -eq 3 ]] && break
      sleep $((attempt * 30))
    done
    return 1
  fi
}
