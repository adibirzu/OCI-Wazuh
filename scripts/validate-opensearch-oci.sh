#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/wazuh-ssh.sh"

mkdir -p "$REPO_ROOT/artifacts/validation"
evidence="$REPO_ROOT/artifacts/validation/M7-opensearch-oci-validation.txt"

wazuh_ssh 'sudo bash -lc '"'"'
set -euo pipefail
. /etc/oci-wazuh-demo/opensearch.env
audit_count="$(curl -sk -u "$OCI_WAZUH_OPENSEARCH_USERNAME:$OCI_WAZUH_OPENSEARCH_PASSWORD" "$OCI_WAZUH_OPENSEARCH_URL/oci-audit-*/_count" | python3 -c "import json,sys; print(json.load(sys.stdin).get(\"count\",0))")"
flow_count="$(curl -sk -u "$OCI_WAZUH_OPENSEARCH_USERNAME:$OCI_WAZUH_OPENSEARCH_PASSWORD" "$OCI_WAZUH_OPENSEARCH_URL/oci-flow-*/_count" | python3 -c "import json,sys; print(json.load(sys.stdin).get(\"count\",0))")"
audit_template="$(curl -sk -u "$OCI_WAZUH_OPENSEARCH_USERNAME:$OCI_WAZUH_OPENSEARCH_PASSWORD" "$OCI_WAZUH_OPENSEARCH_URL/_index_template/oci-audit-template" | python3 -c "import json,sys; print(\"ready\" if json.load(sys.stdin).get(\"index_templates\") else \"missing\")")"
flow_template="$(curl -sk -u "$OCI_WAZUH_OPENSEARCH_USERNAME:$OCI_WAZUH_OPENSEARCH_PASSWORD" "$OCI_WAZUH_OPENSEARCH_URL/_index_template/oci-flow-template" | python3 -c "import json,sys; print(\"ready\" if json.load(sys.stdin).get(\"index_templates\") else \"missing\")")"
dashboard_status=skipped
if [[ -n "${OCI_WAZUH_DASHBOARD_URL:-}" ]]; then
  dashboard_status="$(curl -sk -u "$OCI_WAZUH_OPENSEARCH_USERNAME:$OCI_WAZUH_OPENSEARCH_PASSWORD" -H "osd-xsrf: true" "$OCI_WAZUH_DASHBOARD_URL/api/saved_objects/dashboard/oci-logs-overview" | python3 -c "import json,sys; data=json.load(sys.stdin); print(\"ready\" if data.get(\"id\") == \"oci-logs-overview\" else \"missing\")")"
fi
echo "opensearch_oci=green"
echo "oci_audit_count=$audit_count"
echo "oci_flow_count=$flow_count"
echo "oci_audit_template=$audit_template"
echo "oci_flow_template=$flow_template"
echo "dashboard.oci_logs_overview=$dashboard_status"
test "$audit_count" -gt 0
test "$flow_count" -gt 0
test "$audit_template" = ready
test "$flow_template" = ready
'"'"'' | tee "$evidence"
