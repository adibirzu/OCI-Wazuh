#!/usr/bin/env bash
set -euo pipefail

run_id="$(python3 -c 'import json; print(json.load(open("artifacts/validation/_run.json"))["run_id"])')"
export VALIDATION_RUN_ID="$run_id"
export M11_RUN_INITIALIZED=true

make e2e
make validate-bootstrap
make validate-windows
make validate-real-oci-logs
make validate-management-dashboard
make log-analytics-freshness
if [[ "${TF_VAR_create_oci_opensearch:-false}" == "true" ]]; then
  make opensearch-oci
  make validate-opensearch-oci
fi
make m11-gate
