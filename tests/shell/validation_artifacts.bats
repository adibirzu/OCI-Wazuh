#!/usr/bin/env bats

setup() {
  export TEST_ROOT="${BATS_TEST_TMPDIR}/validation"
  mkdir -p "${TEST_ROOT}"
  printf 'state=failed\n' > "${TEST_ROOT}/stale.txt"
}

@test "validation run initialization removes stale artifacts" {
  run bash scripts/validation-run.sh --directory "${TEST_ROOT}" --mode test --run-id bats-run

  [ "$status" -eq 0 ]
  [ ! -e "${TEST_ROOT}/stale.txt" ]
  run python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); print(p["run_id"], p["state"])' "${TEST_ROOT}/_run.json"
  [ "$output" = "bats-run green" ]
}

@test "Wazuh SSH defaults to bastion and always rejects direct public access" {
  outputs="${BATS_TEST_TMPDIR}/outputs.json"
  cat >"${outputs}" <<'JSON'
{"wazuh_public_ip":{"value":"198.51.100.8"},"wazuh_private_ip":{"value":"192.0.2.10"},"bastion_public_ip":{"value":"198.51.100.9"}}
JSON

  run env OUTPUTS="$outputs" bash -c 'WAZUH_TF_OUTPUT_JSON="$OUTPUTS"; source scripts/wazuh-ssh.sh; wazuh_resolve_target'
  [ "$status" -eq 0 ]
  [[ "$output" == bastion\|*\|192.0.2.10\|198.51.100.9 ]]

  run env OUTPUTS="$outputs" bash -c 'WAZUH_TF_OUTPUT_JSON="$OUTPUTS"; WAZUH_SSH_MODE=direct; source scripts/wazuh-ssh.sh; wazuh_resolve_target'
  [ "$status" -ne 0 ]
  [[ "$output" == *"development-only"* ]]

  run env OUTPUTS="$outputs" bash -c 'WAZUH_TF_OUTPUT_JSON="$OUTPUTS"; WAZUH_SSH_MODE=direct; ALLOW_PUBLIC_WAZUH_SSH=true; source scripts/wazuh-ssh.sh; wazuh_resolve_target'
  [ "$status" -ne 0 ]
  [[ "$output" == *"forbidden"* ]]
}
