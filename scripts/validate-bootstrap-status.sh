#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
outputs="$repo_root/artifacts/runtime/terraform-output.json"
artifacts="$repo_root/artifacts/validation"
profile="${OCI_PROFILE:-${OCI_CLI_PROFILE:-DEFAULT}}"

read_outputs() {
  python3 - "$outputs" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
print(payload["bootstrap_object_storage_namespace"]["value"])
print(payload["bootstrap_object_storage_bucket"]["value"])
print(payload["bootstrap_status"]["value"]["expected_linux_markers"])
PY
}

context=()
while IFS= read -r line; do
  context+=("$line")
done < <(read_outputs)
namespace="${context[0]}"
bucket="${context[1]}"
expected="${context[2]}"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/oci-wazuh-bootstrap-status.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT

state=failed
green_count=0
components=""
for attempt in $(seq 1 45); do
  names_json="$(oci --profile "$profile" os object list \
    --namespace "$namespace" --bucket-name "$bucket" --prefix status/ --all \
    --query 'data[].name' --output json)"
  mapfile_path="$temporary/names.txt"
  python3 - "$names_json" >"$mapfile_path" <<'PY'
import json
import sys

for name in json.loads(sys.argv[1]):
    suffix = name.removeprefix("status/")
    if suffix.endswith(".json") and "/" not in suffix:
        print(name)
PY
  names=()
  while IFS= read -r name; do
    [[ -n "$name" ]] && names+=("$name")
  done <"$mapfile_path"
  if [[ "${#names[@]}" -ge "$expected" ]]; then
    for index in "${!names[@]}"; do
      oci --profile "$profile" os object get \
        --namespace "$namespace" --bucket-name "$bucket" --name "${names[$index]}" \
        --file "$temporary/$index.json" >/dev/null
    done
    read -r green_count components < <(python3 - "$temporary" <<'PY'
import json
import pathlib
import sys

payloads = [json.loads(path.read_text(encoding="utf-8")) for path in pathlib.Path(sys.argv[1]).glob("*.json")]
green = [item for item in payloads if item.get("state") == "green"]
print(len(green), ",".join(sorted({str(item.get("component", "unknown")) for item in green})))
PY
    )
    if [[ "$green_count" -ge "$expected" ]]; then
      state=green
      break
    fi
  fi
  echo "waiting for verified bootstrap markers ($attempt/45)" >&2
  sleep 20
done

python3 - "$artifacts" "$state" "$expected" "$green_count" "$components" <<'PY'
import json
import sys
from pathlib import Path

from m11.artifacts import write_gate

directory, state, expected, green, components = sys.argv[1:]
directory = Path(directory)
context = json.loads((directory / "_run.json").read_text(encoding="utf-8"))
write_gate(directory, context, "bootstrap", state, {
    "components": components.split(",") if components else [],
    "expected_markers": int(expected),
    "green_markers": int(green),
})
PY

echo "bootstrap=$state green_markers=$green_count expected_markers=$expected"
test "$state" = green
