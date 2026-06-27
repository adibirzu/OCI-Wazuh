#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/wazuh-ssh.sh"

mkdir -p "$REPO_ROOT/artifacts/validation"
evidence="$REPO_ROOT/artifacts/validation/M7-opensearch-oci.txt"

backend="${OCI_WAZUH_OPENSEARCH_BACKEND:-aio}"
if [[ "$backend" != "aio" && "$backend" != "oci_opensearch" ]]; then
  echo "OCI_WAZUH_OPENSEARCH_BACKEND must be aio or oci_opensearch" >&2
  exit 2
fi

tf_output_value() {
  local key="$1"
  python3 - "$REPO_ROOT/artifacts/runtime/terraform-output.json" "$key" <<'PY'
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

tfvar_value() {
  local key="$1"
  local tfvars="${TFVARS_FILE:-$REPO_ROOT/terraform/terraform.tfvars}"
  [[ -f "$tfvars" ]] || return 0
  awk -F= -v k="$key" '$1 ~ "^[[:space:]]*" k "[[:space:]]*$" {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); gsub(/^"|"$/, "", $2); print $2; exit}' "$tfvars"
}

if [[ "$backend" == "oci_opensearch" ]]; then
  export OCI_WAZUH_OPENSEARCH_URL="${OCI_WAZUH_OPENSEARCH_URL:-$(tf_output_value oci_opensearch_url)}"
  export OCI_WAZUH_OPENSEARCH_USERNAME="${OCI_WAZUH_OPENSEARCH_USERNAME:-$(tfvar_value oci_opensearch_master_user_name)}"
  export OCI_WAZUH_OPENSEARCH_PASSWORD="${OCI_WAZUH_OPENSEARCH_PASSWORD:-$(tfvar_value oci_opensearch_master_password)}"
  export OCI_WAZUH_DASHBOARD_URL="${OCI_WAZUH_DASHBOARD_URL:-$(tf_output_value oci_opensearch_dashboard_url)}"
fi

remote_script="$(mktemp "${TMPDIR:-/tmp}/oci-wazuh-opensearch.XXXXXX")"
remote_config="$(mktemp "${TMPDIR:-/tmp}/oci-wazuh-opensearch-config.XXXXXX")"
cleanup_local() {
  rm -f "$remote_script" "$remote_config"
}
trap cleanup_local EXIT
OCI_WAZUH_OPENSEARCH_BACKEND="$backend" jq -n \
  '{backend: env.OCI_WAZUH_OPENSEARCH_BACKEND,
    url: (env.OCI_WAZUH_OPENSEARCH_URL // ""),
    username: (env.OCI_WAZUH_OPENSEARCH_USERNAME // ""),
    password: (env.OCI_WAZUH_OPENSEARCH_PASSWORD // ""),
    verify_ssl: (env.OCI_WAZUH_OPENSEARCH_VERIFY_SSL // "false"),
    dashboard_url: (env.OCI_WAZUH_DASHBOARD_URL // "")}' \
  >"$remote_config"
chmod 0600 "$remote_config"
cat > "$remote_script" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

config_path=/tmp/oci-wazuh-opensearch-config.json
trap 'rm -f "$config_path"' EXIT
test -r "$config_path"
backend="$(jq -r .backend "$config_path")"
url="$(jq -r .url "$config_path")"
username="$(jq -r .username "$config_path")"
os_value="$(jq -r .password "$config_path")"
verify_ssl="$(jq -r .verify_ssl "$config_path")"
dashboard_url="$(jq -r .dashboard_url "$config_path")"

extract_password() {
  if [[ -f /opt/oci-wazuh-demo/wazuh-install-files.tar ]]; then
    tar -xOf /opt/oci-wazuh-demo/wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt 2>/dev/null |
      awk -F"'" '/indexer_username: '\''admin'\''/{getline; print $2; exit}'
    return 0
  fi
  awk '/User: admin/{getline; sub(/^.*Password: /, ""); print; exit}' /var/log/oci-wazuh-demo/wazuh-install.log 2>/dev/null || true
}

if [[ "$backend" == "aio" ]]; then
  url="${url:-https://127.0.0.1:9200}"
  username="${username:-admin}"
  os_value="${os_value:-$(extract_password)}"
  dashboard_url="${dashboard_url:-https://127.0.0.1:443}"
fi

if [[ -z "$url" || -z "$username" || -z "$os_value" ]]; then
  echo "missing OpenSearch URL/username/password for backend $backend" >&2
  exit 2
fi

curl_opts=(-fsS)
if [[ "$verify_ssl" != "true" ]]; then
  curl_opts+=(-k)
fi
auth=(-u "${username}:${os_value}")

sudo mkdir -p /etc/oci-wazuh-demo
sudo install -o root -g root -m 0600 /dev/null /etc/oci-wazuh-demo/opensearch.env
{
  printf '%s=%s\n' OCI_WAZUH_OPENSEARCH_ENABLED true
  printf '%s=%s\n' OCI_WAZUH_OPENSEARCH_BACKEND "$backend"
  printf '%s=%s\n' OCI_WAZUH_OPENSEARCH_URL "$url"
  printf '%s=%s\n' OCI_WAZUH_OPENSEARCH_USERNAME "$username"
  printf '%s=%s\n' OCI_WAZUH_OPENSEARCH_PASSWORD "$os_value"
  printf '%s=%s\n' OCI_WAZUH_OPENSEARCH_VERIFY_SSL "$verify_ssl"
  printf '%s=%s\n' OCI_WAZUH_OPENSEARCH_AUDIT_INDEX_PREFIX oci-audit
  printf '%s=%s\n' OCI_WAZUH_OPENSEARCH_FLOW_INDEX_PREFIX oci-flow
  printf '%s=%s\n' OCI_WAZUH_DASHBOARD_URL "$dashboard_url"
} | sudo tee /etc/oci-wazuh-demo/opensearch.env >/dev/null

audit_template='{
  "index_patterns": ["oci-audit-*"],
  "template": {
    "settings": {"number_of_shards": 1, "number_of_replicas": 0},
    "mappings": {
      "dynamic": true,
      "properties": {
        "@timestamp": {"type": "date"},
        "source": {"type": "keyword"},
        "eventType": {"type": "keyword"},
        "principalName": {"type": "keyword"},
        "sourceIp": {"type": "ip", "ignore_malformed": true},
        "compartmentId": {"type": "keyword"},
        "event.dataset": {"type": "keyword"},
        "cloud.provider": {"type": "keyword"}
      }
    }
  }
}'
flow_template='{
  "index_patterns": ["oci-flow-*"],
  "template": {
    "settings": {"number_of_shards": 1, "number_of_replicas": 0},
    "mappings": {
      "dynamic": true,
      "properties": {
        "@timestamp": {"type": "date"},
        "source": {"type": "keyword"},
        "srcaddr": {"type": "ip", "ignore_malformed": true},
        "dstaddr": {"type": "ip", "ignore_malformed": true},
        "srcport": {"type": "integer", "ignore_malformed": true},
        "dstport": {"type": "integer", "ignore_malformed": true},
        "protocol": {"type": "integer", "ignore_malformed": true},
        "action": {"type": "keyword"},
        "bytes": {"type": "long", "ignore_malformed": true},
        "packets": {"type": "long", "ignore_malformed": true},
        "event.dataset": {"type": "keyword"},
        "cloud.provider": {"type": "keyword"}
      }
    }
  }
}'

curl "${curl_opts[@]}" "${auth[@]}" -H 'Content-Type: application/json' -X PUT "$url/_index_template/oci-audit-template" -d "$audit_template" >/dev/null
curl "${curl_opts[@]}" "${auth[@]}" -H 'Content-Type: application/json' -X PUT "$url/_index_template/oci-flow-template" -d "$flow_template" >/dev/null

if [[ -n "$dashboard_url" ]]; then
  osd_headers=(-H 'Content-Type: application/json' -H 'osd-xsrf: true')
  curl "${curl_opts[@]}" "${auth[@]}" "${osd_headers[@]}" \
    -X POST "$dashboard_url/api/saved_objects/index-pattern/oci-audit-*?overwrite=true" \
    -d '{"attributes":{"title":"oci-audit-*","timeFieldName":"@timestamp"}}' >/dev/null
  curl "${curl_opts[@]}" "${auth[@]}" "${osd_headers[@]}" \
    -X POST "$dashboard_url/api/saved_objects/index-pattern/oci-flow-*?overwrite=true" \
    -d '{"attributes":{"title":"oci-flow-*","timeFieldName":"@timestamp"}}' >/dev/null

  curl "${curl_opts[@]}" "${auth[@]}" "${osd_headers[@]}" \
    -X POST "$dashboard_url/api/saved_objects/search/oci-audit-latest?overwrite=true" \
    -d '{"attributes":{"title":"OCI Audit - Latest Events","description":"Latest normalized OCI Audit events","columns":["@timestamp","eventType","principalName","sourceIp","compartmentId"],"sort":[["@timestamp","desc"]],"kibanaSavedObjectMeta":{"searchSourceJSON":"{\"index\":\"oci-audit-*\",\"query\":{\"language\":\"kuery\",\"query\":\"\"},\"filter\":[]}"}}}' >/dev/null
  curl "${curl_opts[@]}" "${auth[@]}" "${osd_headers[@]}" \
    -X POST "$dashboard_url/api/saved_objects/search/oci-flow-denied?overwrite=true" \
    -d '{"attributes":{"title":"OCI Flow - Denied Traffic","description":"Rejected OCI VCN Flow events","columns":["@timestamp","srcaddr","dstaddr","dstport","protocol","action","bytes","packets"],"sort":[["@timestamp","desc"]],"kibanaSavedObjectMeta":{"searchSourceJSON":"{\"index\":\"oci-flow-*\",\"query\":{\"language\":\"kuery\",\"query\":\"action: REJECT\"},\"filter\":[]}"}}}' >/dev/null

  dashboard_body='{
    "attributes": {
      "title": "OCI Logs Overview",
      "description": "Dedicated OCI Audit and VCN Flow Log dashboard for the OCI Wazuh demo.",
      "panelsJSON": "[{\"version\":\"2.19.0\",\"type\":\"search\",\"id\":\"oci-audit-latest\",\"panelIndex\":\"1\",\"embeddableConfig\":{},\"gridData\":{\"x\":0,\"y\":0,\"w\":24,\"h\":15,\"i\":\"1\"}},{\"version\":\"2.19.0\",\"type\":\"search\",\"id\":\"oci-flow-denied\",\"panelIndex\":\"2\",\"embeddableConfig\":{},\"gridData\":{\"x\":24,\"y\":0,\"w\":24,\"h\":15,\"i\":\"2\"}}]",
      "optionsJSON": "{\"useMargins\":true,\"hidePanelTitles\":false}",
      "timeRestore": false,
      "kibanaSavedObjectMeta": {
        "searchSourceJSON": "{\"query\":{\"language\":\"kuery\",\"query\":\"\"},\"filter\":[]}"
      }
    },
    "references": [
      {"name":"panel_1","type":"search","id":"oci-audit-latest"},
      {"name":"panel_2","type":"search","id":"oci-flow-denied"}
    ]
  }'
  curl "${curl_opts[@]}" "${auth[@]}" "${osd_headers[@]}" \
    -X POST "$dashboard_url/api/saved_objects/dashboard/oci-logs-overview?overwrite=true" \
    -d "$dashboard_body" >/dev/null
fi

systemctl daemon-reload
systemctl restart oci-wazuh-audit-consumer.service
systemctl restart oci-wazuh-flow-consumer.service

echo "opensearch_backend=$backend"
echo "oci_audit_index=oci-audit-*"
echo "oci_flow_index=oci-flow-*"
echo "index_templates=ready"
if [[ -n "${dashboard_url:-}" ]]; then
  echo "dashboard_data_views=ready"
  echo "dashboard.oci_logs_overview=ready"
else
  echo "dashboard_data_views=skipped_external_backend"
fi
SH

chmod +x "$remote_script"
wazuh_scp_to "$remote_script" "/tmp/oci-wazuh-opensearch.sh"
wazuh_scp_to "$remote_config" "/tmp/oci-wazuh-opensearch-config.json"
rm -f "$remote_script" "$remote_config"

wazuh_ssh "sudo bash /tmp/oci-wazuh-opensearch.sh" | tee "$evidence"
