#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/wazuh-ssh.sh"

mkdir -p "$REPO_ROOT/artifacts/validation"
evidence="$REPO_ROOT/artifacts/validation/M6-M7-wazuh-content.txt"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/oci-wazuh-content.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/decoders" "$tmpdir/rules" "$tmpdir/consumer"
cp "$REPO_ROOT"/wazuh/decoders/*.xml "$tmpdir/decoders/"
cp "$REPO_ROOT"/wazuh/rules/*.xml "$tmpdir/rules/"
cp "$REPO_ROOT"/wazuh/consumer/oci_log_consumer.py "$tmpdir/consumer/"

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
if value is None:
    print("")
elif isinstance(value, list):
    print(",".join(str(item) for item in value))
else:
    print(value)
PY
}

tfvar_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 ~ "^[[:space:]]*" k "[[:space:]]*$" {gsub(/[ \"]/,"",$2); print $2; exit}' "$REPO_ROOT/terraform/terraform.tfvars" 2>/dev/null || true
}

ingestion_mode="$(tf_output_value oci_log_ingestion_mode)"
if [[ -n "$ingestion_mode" ]]; then
  audit_compartment_id="$(tfvar_value audit_log_resource_id)"
  audit_in_subtree="false"
  if [[ -z "$audit_compartment_id" ]]; then
    audit_compartment_id="$(tfvar_value tenancy_id)"
    audit_in_subtree="true"
  fi
  if [[ -z "$audit_compartment_id" ]]; then
    audit_compartment_id="$(tfvar_value compartment_id)"
  fi
  cat > "$tmpdir/consumer.env" <<EOF
OCI_WAZUH_INGESTION_MODE=$ingestion_mode
OCI_WAZUH_PROJECT_NAME=$(tf_output_value project_name)
OCI_WAZUH_STREAM_ID=$(tf_output_value oci_log_stream_id)
OCI_WAZUH_STREAM_ENDPOINT=$(tf_output_value oci_log_stream_messages_endpoint)
OCI_WAZUH_OBJECT_NAMESPACE=$(tf_output_value oci_log_object_storage_namespace)
OCI_WAZUH_OBJECT_BUCKET=$(tf_output_value oci_log_object_storage_bucket)
OCI_WAZUH_OBJECT_PREFIX=$(tf_output_value oci_log_object_storage_prefix)
OCI_WAZUH_COMPARTMENT_ID=$(tfvar_value compartment_id)
OCI_WAZUH_AUDIT_COMPARTMENT_ID=$audit_compartment_id
OCI_WAZUH_AUDIT_COMPARTMENT_IN_SUBTREE=$audit_in_subtree
OCI_REGION=$(tfvar_value region)
EOF
else
  : > "$tmpdir/consumer.env"
fi

COPYFILE_DISABLE=1 tar -C "$tmpdir" -czf "$tmpdir/oci-wazuh-content.tgz" decoders rules consumer consumer.env
wazuh_scp_to "$tmpdir/oci-wazuh-content.tgz" "/tmp/oci-wazuh-content.tgz"

wazuh_ssh 'set -euo pipefail
sudo mkdir -p /opt/oci-wazuh-demo/content /opt/oci-wazuh-demo/consumer /etc/oci-wazuh-demo /var/ossec/logs/oci /var/lib/oci-wazuh-consumer
sudo tar -xzf /tmp/oci-wazuh-content.tgz -C /opt/oci-wazuh-demo/content
sudo install -o root -g wazuh -m 0640 /opt/oci-wazuh-demo/content/decoders/*.xml /var/ossec/etc/decoders/
sudo install -o root -g wazuh -m 0640 /opt/oci-wazuh-demo/content/rules/*.xml /var/ossec/etc/rules/
sudo install -o root -g root -m 0755 /opt/oci-wazuh-demo/content/consumer/oci_log_consumer.py /opt/oci-wazuh-demo/consumer/oci_log_consumer.py
sudo install -o root -g root -m 0600 /opt/oci-wazuh-demo/content/consumer.env /etc/oci-wazuh-demo/consumer.env
sudo touch /var/ossec/logs/oci/audit.json /var/ossec/logs/oci/flow.json
sudo chown -R wazuh:wazuh /var/ossec/logs/oci
sudo chown -R root:root /var/lib/oci-wazuh-consumer
sudo chmod 0750 /var/ossec/logs/oci
sudo chmod 0640 /var/ossec/logs/oci/audit.json /var/ossec/logs/oci/flow.json
if ! /opt/oci-wazuh-demo/venv/bin/python3 -c "import oci" >/dev/null 2>&1; then
  if ! sudo python3 -m venv /opt/oci-wazuh-demo/venv >/dev/null 2>&1; then
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3-venv python3-pip
    sudo python3 -m venv /opt/oci-wazuh-demo/venv
  fi
  sudo /opt/oci-wazuh-demo/venv/bin/python3 -m pip install --upgrade pip oci
fi
sudo tee /usr/local/bin/oci-wazuh-consumer-start.sh >/dev/null <<'"'"'SH'"'"'
#!/usr/bin/env bash
set -euo pipefail
role="${1:-flow}"
env_file=/etc/oci-wazuh-demo/consumer.env
if [[ -f "$env_file" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
fi
opensearch_env=/etc/oci-wazuh-demo/opensearch.env
if [[ -f "$opensearch_env" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$opensearch_env"
  set +a
fi
mode="${OCI_WAZUH_INGESTION_MODE:-}"
project="${OCI_WAZUH_PROJECT_NAME:-oci-wazuh-demo}"
python_bin="${OCI_WAZUH_PYTHON:-/opt/oci-wazuh-demo/venv/bin/python3}"
if [[ ! -x "$python_bin" ]]; then
  python_bin=python3
fi
base=(/opt/oci-wazuh-demo/consumer/oci_log_consumer.py --output-dir /var/ossec/logs/oci --group-name "$project" --instance-name "$(hostname)" --poll-seconds "${OCI_WAZUH_POLL_SECONDS:-10}")
if [[ "$role" == "audit" ]]; then
  subtree_arg=--no-compartment-id-in-subtree
  if [[ "${OCI_WAZUH_AUDIT_COMPARTMENT_IN_SUBTREE:-false}" == "true" ]]; then
    subtree_arg=--compartment-id-in-subtree
  fi
  exec "$python_bin" "${base[@]}" --state-file /var/lib/oci-wazuh-consumer/audit-state.txt --mode direct_api --source audit --compartment-id "${OCI_WAZUH_AUDIT_COMPARTMENT_ID:-${OCI_WAZUH_COMPARTMENT_ID:?missing audit compartment id}}" "$subtree_arg"
fi
case "$mode" in
  streaming)
    exec "$python_bin" "${base[@]}" --state-file /var/lib/oci-wazuh-consumer/flow-state.txt --mode streaming --source flow --stream-id "${OCI_WAZUH_STREAM_ID:?missing stream id}" --stream-endpoint "${OCI_WAZUH_STREAM_ENDPOINT:?missing stream endpoint}"
    ;;
  object_storage)
    exec "$python_bin" "${base[@]}" --state-file /var/lib/oci-wazuh-consumer/flow-state.txt --mode object_storage --source flow --object-namespace "${OCI_WAZUH_OBJECT_NAMESPACE:?missing namespace}" --object-bucket "${OCI_WAZUH_OBJECT_BUCKET:?missing bucket}" --object-prefix "${OCI_WAZUH_OBJECT_PREFIX:-oci-logs/}"
    ;;
  direct_api)
    echo "direct_api mode has no VCN Flow source; use oci-wazuh-audit-consumer.service for Audit"
    sleep infinity
    ;;
  ""|log_analytics_bridge)
    echo "OCI Wazuh consumer disabled for mode ${mode}"
    sleep infinity
    ;;
  *)
    echo "unsupported OCI_WAZUH_INGESTION_MODE=$mode" >&2
    exit 2
    ;;
esac
SH
sudo chmod 0755 /usr/local/bin/oci-wazuh-consumer-start.sh
sudo tee /etc/systemd/system/oci-wazuh-flow-consumer.service >/dev/null <<'"'"'UNIT'"'"'
[Unit]
Description=OCI Wazuh VCN Flow Log consumer
After=network-online.target wazuh-manager.service
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=-/etc/oci-wazuh-demo/consumer.env
EnvironmentFile=-/etc/oci-wazuh-demo/opensearch.env
ExecStart=/usr/local/bin/oci-wazuh-consumer-start.sh flow
Restart=always
RestartSec=15
User=root
Group=root

[Install]
WantedBy=multi-user.target
UNIT
sudo tee /etc/systemd/system/oci-wazuh-audit-consumer.service >/dev/null <<'"'"'UNIT'"'"'
[Unit]
Description=OCI Wazuh Audit API consumer
After=network-online.target wazuh-manager.service
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=-/etc/oci-wazuh-demo/consumer.env
EnvironmentFile=-/etc/oci-wazuh-demo/opensearch.env
ExecStart=/usr/local/bin/oci-wazuh-consumer-start.sh audit
Restart=always
RestartSec=15
User=root
Group=root

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl disable --now oci-wazuh-consumer.service >/dev/null 2>&1 || true
if sudo grep -q "^OCI_WAZUH_INGESTION_MODE=\\(streaming\\|object_storage\\|direct_api\\)" /etc/oci-wazuh-demo/consumer.env; then
  sudo systemctl enable --now oci-wazuh-audit-consumer.service
  sudo systemctl restart oci-wazuh-audit-consumer.service
else
  sudo systemctl disable --now oci-wazuh-audit-consumer.service >/dev/null 2>&1 || true
fi
if sudo grep -q "^OCI_WAZUH_INGESTION_MODE=\\(streaming\\|object_storage\\)" /etc/oci-wazuh-demo/consumer.env; then
  sudo systemctl enable --now oci-wazuh-flow-consumer.service
  sudo systemctl restart oci-wazuh-flow-consumer.service
else
  sudo systemctl disable --now oci-wazuh-flow-consumer.service >/dev/null 2>&1 || true
fi
sudo python3 - <<'"'"'PY'"'"'
from pathlib import Path

path = Path("/var/ossec/etc/ossec.conf")
text = path.read_text()
blocks = [
    ("oci-audit-json", "/var/ossec/logs/oci/audit.json"),
    ("oci-flow-json", "/var/ossec/logs/oci/flow.json"),
]
insert = []
for label, location in blocks:
    if location not in text:
        insert.append(f"""
  <localfile>
    <log_format>json</log_format>
    <location>{location}</location>
  </localfile>
""")
if insert:
    marker = "</ossec_config>"
    text = text.replace(marker, "".join(insert) + "\n" + marker)
    path.write_text(text)
PY
sudo /var/ossec/bin/wazuh-analysisd -t
sudo systemctl restart wazuh-manager
sleep 5
status="$(sudo /var/ossec/bin/wazuh-control status || true)"
printf "%s\n" "$status"
for service in wazuh-modulesd wazuh-logcollector wazuh-remoted wazuh-syscheckd wazuh-analysisd wazuh-execd wazuh-db wazuh-authd wazuh-apid; do
  printf "%s\n" "$status" | grep -q "${service} is running"
done
	'

{
  echo "wazuh_content=deployed"
  echo "oci_decoders=ready"
  echo "oci_rules=ready"
  echo "oci_logcollector=ready"
  echo "consumer=ready"
  echo "consumer_systemd=ready"
} > "$evidence"

cat "$evidence"
