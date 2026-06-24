#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/validation
rm -f artifacts/validation/M3-dashboard.txt artifacts/validation/M3-wazuh-status.txt artifacts/validation/M4-agent-control.txt artifacts/validation/M4-fim-marker-alerts.txt artifacts/validation/M4-fim-forced-scan-alerts.txt artifacts/validation/e2e.txt

if [[ "${1:-}" == "--dry-run" ]]; then
  echo "dry_run=true" > artifacts/validation/e2e-dry-run.txt
  exit 0
fi

outputs="artifacts/validation/terraform-output.json"
if [[ ! -s "$outputs" ]]; then
  echo "missing $outputs; run make up first" >&2
  exit 2
fi

ssh_last_error="artifacts/validation/ssh-last-error.txt"
bastion="$(python3 -c 'import json; print(json.load(open("artifacts/validation/terraform-output.json"))["bastion_public_ip"]["value"])')"
wazuh="$(python3 -c 'import json; print(json.load(open("artifacts/validation/terraform-output.json"))["wazuh_private_ip"]["value"])')"
wazuh_public="$(python3 -c 'import json; data=json.load(open("artifacts/validation/terraform-output.json")); print(data.get("wazuh_public_ip", {}).get("value") or "")')"
ol9_public="$(python3 -c 'import json; data=json.load(open("artifacts/validation/terraform-output.json")); print(data.get("ol9_agent_public_ip", {}).get("value") or "")')"
ubuntu_public="$(python3 -c 'import json; data=json.load(open("artifacts/validation/terraform-output.json")); print(data.get("ubuntu_agent_public_ip", {}).get("value") or "")')"
ssh_key="$(awk -F= '/ssh_private_key_path/{gsub(/[ "]/,"",$2); print $2}' terraform/terraform.tfvars)"

ssh_ctrl_dir="$(mktemp -d "${TMPDIR:-/tmp}/oci-wazuh-ssh.XXXXXX")"
bastion_ctrl="${ssh_ctrl_dir}/bastion"
wazuh_direct_ctrl="${ssh_ctrl_dir}/wazuh-direct"

cleanup() {
  if [[ -n "${bastion_user:-}" ]]; then
    ssh -S "$bastion_ctrl" -O exit "${bastion_user}@${bastion}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${wazuh_user:-}" && -S "$wazuh_direct_ctrl" ]]; then
    ssh -S "$wazuh_direct_ctrl" -O exit "${wazuh_user}@${wazuh_public}" >/dev/null 2>&1 || true
  fi
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
bastion_user=""
wazuh_user=""
wazuh_access_mode=""
bastion_ready=false

try_bastion_user() {
  local user="$1"
  {
    echo "probe=bastion user=${user} ts=$(date -u +%FT%TZ)"
    ssh "${ssh_opts[@]}" "${user}@${bastion}" "echo ok"
  } >"$ssh_last_error" 2>&1
}

wait_for_bastion_user() {
  local stable_successes=0
  local max_attempts=40

  if [[ -n "$wazuh_public" ]]; then
    max_attempts=5
  fi

  for attempt in $(seq 1 "$max_attempts"); do
    for candidate_user in opc ubuntu; do
      if try_bastion_user "$candidate_user"; then
        stable_successes=$((stable_successes + 1))
        bastion_user="$candidate_user"

        if (( stable_successes >= 2 )); then
          return 0
        fi
      fi
    done

    echo "waiting for stable bastion SSH (${attempt}/${max_attempts}); last error in ${ssh_last_error}" >&2
    sleep 15
  done

  return 1
}

start_bastion_mux() {
  if ! ssh "${ssh_opts[@]}" -M -N -f -o "ControlPath=${bastion_ctrl}" -o ControlPersist=600 "${bastion_user}@${bastion}" >"$ssh_last_error" 2>&1; then
    return 1
  fi

  for _ in {1..10}; do
    [[ -S "$bastion_ctrl" ]] && break
    sleep 1
  done

  ssh -o "ControlPath=${bastion_ctrl}" -O check "${bastion_user}@${bastion}" >"$ssh_last_error" 2>&1
}

run_wazuh_ssh() {
  local user="$1"
  local command="$2"
  local proxy_cmd
  proxy_cmd="ssh -S ${bastion_ctrl} -o ControlMaster=no -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null -W %h:%p ${bastion_user}@${bastion}"

  {
    echo "probe=wazuh user=${user} ts=$(date -u +%FT%TZ)"
    ssh "${ssh_opts[@]}" -o "ProxyCommand=${proxy_cmd}" "${user}@${wazuh}" "$command"
  } >"$ssh_last_error" 2>&1
}

run_wazuh_ssh_stream() {
  local user="$1"
  local command="$2"
  local proxy_cmd
  proxy_cmd="ssh -S ${bastion_ctrl} -o ControlMaster=no -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null -W %h:%p ${bastion_user}@${bastion}"

  ssh "${ssh_opts[@]}" -o "ProxyCommand=${proxy_cmd}" "${user}@${wazuh}" "$command"
}

run_wazuh_direct() {
  local user="$1"
  local command="$2"

  {
    echo "probe=wazuh-public user=${user} ts=$(date -u +%FT%TZ)"
    ssh "${ssh_opts[@]}" "${user}@${wazuh_public}" "$command"
  } >"$ssh_last_error" 2>&1
}

run_wazuh_direct_stream() {
  local user="$1"
  local command="$2"

  if [[ -S "$wazuh_direct_ctrl" ]]; then
    ssh "${ssh_opts[@]}" -S "$wazuh_direct_ctrl" "${user}@${wazuh_public}" "$command"
  else
    ssh "${ssh_opts[@]}" "${user}@${wazuh_public}" "$command"
  fi
}

start_wazuh_direct_mux() {
  if [[ -z "$wazuh_public" ]]; then
    return 1
  fi

  if ! ssh "${ssh_opts[@]}" -M -N -f -o "ControlPath=${wazuh_direct_ctrl}" -o ControlPersist=600 "${wazuh_user}@${wazuh_public}" >"$ssh_last_error" 2>&1; then
    return 1
  fi

  for _ in {1..10}; do
    [[ -S "$wazuh_direct_ctrl" ]] && break
    sleep 1
  done

  ssh -o "ControlPath=${wazuh_direct_ctrl}" -O check "${wazuh_user}@${wazuh_public}" >"$ssh_last_error" 2>&1
}

run_agent_direct() {
  local user="$1"
  local host="$2"
  local command="$3"

  for attempt in {1..5}; do
    if ssh "${ssh_opts[@]}" "${user}@${host}" "$command"; then
      return 0
    fi
    echo "waiting for agent SSH ${user}@${host} (${attempt}/5)" >&2
    sleep 20
  done

  return 1
}

redact_validation_stream() {
  sed -E \
    -e 's/ocid1[[:alnum:]._-]+/<OCI_OCID>/g' \
    -e 's/"ip":"[^"]+"/"ip":"<REDACTED_IP>"/g' \
    -e 's/\b(10|130|161|144|129|141|82|109)\.[0-9]+\.[0-9]+\.[0-9]+\b/<REDACTED_IP>/g'
}

if wait_for_bastion_user; then
  if start_bastion_mux; then
    bastion_ready=true
  else
    echo "could not establish bastion SSH ControlMaster; last error follows" >&2
    tail -20 "$ssh_last_error" >&2 || true
  fi
else
  echo "could not reach bastion as opc or ubuntu; last error follows" >&2
  tail -20 "$ssh_last_error" >&2 || true
fi

if [[ "$bastion_ready" == "true" ]]; then
  wazuh_private_attempts=40
  if [[ -n "$wazuh_public" ]]; then
    wazuh_private_attempts=5
  fi

  for attempt in $(seq 1 "$wazuh_private_attempts"); do
    for candidate_user in opc ubuntu; do
      if run_wazuh_ssh "$candidate_user" "test -f /var/log/cloud-init-output.log"; then
        wazuh_user="$candidate_user"
        wazuh_access_mode="bastion"
        break 2
      fi
    done
    echo "waiting for Wazuh SSH (${attempt}/${wazuh_private_attempts}); last error in ${ssh_last_error}" >&2
    sleep 15
  done
else
  echo "bastion validation degraded; private Wazuh SSH path skipped" > artifacts/validation/M2-bastion-connectivity.txt
fi

if [[ -z "$wazuh_user" && -z "$wazuh_public" ]]; then
  if [[ "$bastion_ready" == "true" ]]; then
    echo "could not reach Wazuh host through bastion as opc or ubuntu; last error follows" >&2
  else
    echo "could not reach bastion and no Wazuh public IP fallback is available; last error follows" >&2
  fi
  tail -20 "$ssh_last_error" >&2 || true
  exit 1
fi

if [[ -z "$wazuh_user" && -n "$wazuh_public" ]]; then
  if [[ "$bastion_ready" == "true" ]]; then
    echo "Wazuh private SSH through bastion did not converge; trying direct public SSH development fallback" >&2
  else
    echo "Bastion unavailable; trying direct public Wazuh SSH development fallback" >&2
  fi

  for attempt in {1..12}; do
    for candidate_user in opc ubuntu; do
      if run_wazuh_direct "$candidate_user" "test -f /var/log/cloud-init-output.log"; then
        wazuh_user="$candidate_user"
        wazuh_access_mode="direct"
        break 2
      fi
    done
    echo "waiting for direct Wazuh SSH (${attempt}/12); last error in ${ssh_last_error}" >&2
    sleep 10
  done
fi

if [[ -z "$wazuh_user" ]]; then
  echo "could not reach Wazuh host as opc or ubuntu; last error follows" >&2
  tail -20 "$ssh_last_error" >&2 || true
  exit 1
fi

if [[ "$wazuh_access_mode" == "direct" ]]; then
  if ! start_wazuh_direct_mux; then
    echo "could not establish Wazuh direct SSH ControlMaster; last error follows" >&2
    tail -20 "$ssh_last_error" >&2 || true
    exit 1
  fi
fi

if [[ "$wazuh_access_mode" == "direct" ]]; then
  run_wazuh_direct_stream "$wazuh_user" "(sudo /var/ossec/bin/wazuh-control status || sudo journalctl -u wazuh-manager --no-pager -n 80); curl -kfsS https://127.0.0.1:443 >/dev/null" \
    | tee artifacts/validation/M3-wazuh-status.txt

  echo "dashboard=reachable mode=direct" > artifacts/validation/M3-dashboard.txt
else
  run_wazuh_ssh_stream "$wazuh_user" "(sudo /var/ossec/bin/wazuh-control status || sudo journalctl -u wazuh-manager --no-pager -n 80); curl -kfsS https://127.0.0.1:443 >/dev/null" \
    | tee artifacts/validation/M3-wazuh-status.txt

  echo "dashboard=reachable mode=bastion" > artifacts/validation/M3-dashboard.txt
fi

if [[ "$wazuh_access_mode" == "direct" ]]; then
  run_wazuh_direct_stream "$wazuh_user" "sudo /var/ossec/bin/agent_control -l" \
    | tee artifacts/validation/M4-agent-control.txt
else
  run_wazuh_ssh_stream "$wazuh_user" "sudo /var/ossec/bin/agent_control -l" \
    | tee artifacts/validation/M4-agent-control.txt
fi

grep -q "oci-wazuh-demo-ol9-agent.*Active" artifacts/validation/M4-agent-control.txt
grep -q "oci-wazuh-demo-ubuntu-agent.*Active" artifacts/validation/M4-agent-control.txt

if [[ "$wazuh_access_mode" == "direct" ]]; then
  run_wazuh_direct_stream "$wazuh_user" "sudo /var/ossec/bin/agent_control -r -u 001; sudo /var/ossec/bin/agent_control -r -u 002"
else
  run_wazuh_ssh_stream "$wazuh_user" "sudo /var/ossec/bin/agent_control -r -u 001; sudo /var/ossec/bin/agent_control -r -u 002"
fi

sleep 90

fim_query="sudo grep '\"location\":\"syscheck\"' /var/ossec/logs/alerts/alerts.json | grep -E '\"name\":\"oci-wazuh-demo-(ol9|ubuntu)-agent\"' | tail -80"

if [[ "$wazuh_access_mode" == "direct" ]]; then
  run_wazuh_direct_stream "$wazuh_user" "$fim_query" \
    | redact_validation_stream \
    > artifacts/validation/M4-fim-forced-scan-alerts.txt
else
  run_wazuh_ssh_stream "$wazuh_user" "$fim_query" \
    | redact_validation_stream \
    > artifacts/validation/M4-fim-forced-scan-alerts.txt
fi

grep -q '"name":"oci-wazuh-demo-ol9-agent"' artifacts/validation/M4-fim-forced-scan-alerts.txt
grep -q '"name":"oci-wazuh-demo-ubuntu-agent"' artifacts/validation/M4-fim-forced-scan-alerts.txt

{
  echo "fim=forced-syscheck"
  echo "mode=${wazuh_access_mode}"
  echo "ol9_agent=green"
  echo "ubuntu_agent=green"
} > artifacts/validation/M4-fim-marker-alerts.txt

cat artifacts/validation/M4-fim-marker-alerts.txt
echo "e2e=green mode=${wazuh_access_mode}" > artifacts/validation/e2e.txt
