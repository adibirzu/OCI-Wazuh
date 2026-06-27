#!/usr/bin/env bash
set -euo pipefail

status=0
for pattern in \
  'ocid1\.(tenancy|compartment|instance|cluster|networksecuritygroup|loadbalancer|subnet|vnic|bootvolume|loganalytics[a-z]+|user)\.oc1\.[a-z]*\.[a-z0-9]+' \
  '\b(130\.61|161\.153|144\.24|129\.153|141\.147|82\.77|109\.166)\.[0-9]+\.[0-9]+\b' \
  'fr4zqfi''muxtr|aaaadhp5ewo4eaaaa''aaaafs7q|axfo51''x8x2ap|axoxdiev''da5j'; do
  if [[ "${CI:-false}" == "true" ]]; then
    if git grep -qE "$pattern" -- . \
      ':(exclude)AGENTS.md' \
      ':(exclude)tests/**' \
      ':(exclude)m11/redaction.py'; then
      echo "redact_gate=failed pattern_class=sensitive_topology" >&2
      status=1
    fi
  elif git diff --cached -U0 | grep -Eq "$pattern"; then
    echo "redact_gate=failed pattern_class=sensitive_topology" >&2
    status=1
  fi
done
gate_state=green
[[ "$status" -eq 0 ]] || gate_state=failed
if [[ "${CI:-false}" == "true" ]]; then
  echo "redact_gate=$gate_state scope=tracked-tree"
elif git diff --cached --quiet; then
  echo "redact_gate=$gate_state staged_changes=0"
fi
exit "$status"
