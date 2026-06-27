#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
outputs="$repo_root/artifacts/runtime/terraform-output.json"
artifacts="$repo_root/artifacts/validation"
profile="${OCI_PROFILE:-${OCI_CLI_PROFILE:-DEFAULT}}"
source "$repo_root/scripts/wazuh-ssh.sh"

read_context() {
  python3 - "$outputs" <<'PY'
import json
import re
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
print(payload["effective_modes"]["value"]["windows_mode"])
print(payload["effective_modes"]["value"]["reuse_goad_action"])
print(payload["bootstrap_object_storage_namespace"]["value"])
print(payload["bootstrap_object_storage_bucket"]["value"])
for name in payload["windows_target_names"]["value"]:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]{0,62}", name):
        raise SystemExit("unsafe Windows target name in Terraform output")
    print(name)
PY
}

context=()
while IFS= read -r line; do
  context+=("$line")
done < <(read_context)
mode="${context[0]}"
action="${context[1]}"
namespace="${context[2]}"
bucket="${context[3]}"
targets=("${context[@]:4}")
temporary="$(mktemp -d "${TMPDIR:-/tmp}/oci-wazuh-windows-status.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT

state=skipped
missing=()
removed_wazuh=()
active_count=0
sysmon_detection=skipped

if [[ "$mode" != "skip" ]]; then
  state=green
  for target in "${targets[@]}"; do
    object_name="status/windows/${target}-${action}.txt"
    count=0
    for attempt in $(seq 1 45); do
      count="$(oci --profile "$profile" os object list \
        --namespace "$namespace" --bucket-name "$bucket" --prefix "$object_name" \
        --query 'length(data)' --raw-output)"
      [[ "$count" -eq 1 ]] && break
      echo "waiting for Windows marker $target ($attempt/45)" >&2
      sleep 20
    done
    if [[ "$count" -ne 1 ]]; then
      state=failed
      missing+=("$target")
      continue
    fi
    oci --profile "$profile" os object get \
      --namespace "$namespace" --bucket-name "$bucket" --name "$object_name" \
      --file "$temporary/$target.txt" >/dev/null
    if ! grep -Eq '"state"[[:space:]]*:[[:space:]]*"green"' "$temporary/$target.txt"; then
      state=failed
      missing+=("$target")
    fi
    if [[ "$action" == "cleanup" ]] && grep -Eq '"wazuhRemoved"[[:space:]]*:[[:space:]]*true' "$temporary/$target.txt"; then
      removed_wazuh+=("$target")
    fi
  done
fi

if [[ "$state" == "green" && "$action" == "install" ]]; then
  agent_list="$temporary/agent-control.txt"
  for attempt in $(seq 1 45); do
    wazuh_ssh "sudo /var/ossec/bin/agent_control -l" >"$agent_list"
    active_count=0
    for target in "${targets[@]}"; do
      if grep -q "Name: ${target}.*Active" "$agent_list"; then
        active_count=$((active_count + 1))
      fi
    done
    [[ "$active_count" -eq "${#targets[@]}" ]] && break
    echo "waiting for active Windows agents ($attempt/45)" >&2
    sleep 20
  done
  if [[ "$active_count" -ne "${#targets[@]}" ]]; then
    state=failed
  fi

  target_regex="$(IFS='|'; echo "${targets[*]}")"
  sysmon_detection=failed
  for attempt in $(seq 1 45); do
    if wazuh_ssh "sudo grep '\"id\":\"100200\"' /var/ossec/logs/alerts/alerts.json | grep -E '\"name\":\"(${target_regex})\"' | tail -1" >"$temporary/sysmon-alert.txt" && [[ -s "$temporary/sysmon-alert.txt" ]]; then
      sysmon_detection=green
      break
    fi
    echo "waiting for project Sysmon detection ($attempt/45)" >&2
    sleep 20
  done
  [[ "$sysmon_detection" == "green" ]] || state=failed
fi

if [[ "$state" == "green" && "$action" == "cleanup" && "${#removed_wazuh[@]}" -gt 0 ]]; then
  removed_regex="$(IFS='|'; echo "${removed_wazuh[*]}")"
  wazuh_ssh "set -euo pipefail; for id in \$(sudo /var/ossec/bin/agent_control -l | awk '/Name: (${removed_regex})([, ]|$)/ {gsub(\",\", \"\", \$2); print \$2}'); do sudo /var/ossec/bin/manage_agents -r \"\$id\" >/dev/null; done"
fi

python3 - "$artifacts" "$mode" "$action" "$state" "${missing[*]:-}" "$active_count" "$sysmon_detection" <<'PY'
import json
import sys
from pathlib import Path

from m11.artifacts import write_gate

directory, mode, action, state, missing, active, sysmon = sys.argv[1:]
directory = Path(directory)
context = json.loads((directory / "_run.json").read_text(encoding="utf-8"))
details = {
    "action": action,
    "active_agents": int(active),
    "missing_markers": missing.split() if missing else [],
    "sysmon_detection": sysmon,
    "windows_mode": mode,
}
write_gate(directory, context, "windows-cleanup" if action == "cleanup" else "windows-install", state, details)
if action != "cleanup":
    write_gate(directory, context, "windows", state, details)
PY

echo "windows=$state mode=$mode action=$action active_agents=$active_count sysmon_detection=$sysmon_detection"
test "$state" != failed
