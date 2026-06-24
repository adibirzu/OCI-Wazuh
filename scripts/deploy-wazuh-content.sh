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

COPYFILE_DISABLE=1 tar -C "$tmpdir" -czf "$tmpdir/oci-wazuh-content.tgz" decoders rules consumer
wazuh_scp_to "$tmpdir/oci-wazuh-content.tgz" "/tmp/oci-wazuh-content.tgz"

wazuh_ssh 'set -euo pipefail
sudo mkdir -p /opt/oci-wazuh-demo/content /opt/oci-wazuh-demo/consumer /var/ossec/logs/oci
sudo tar -xzf /tmp/oci-wazuh-content.tgz -C /opt/oci-wazuh-demo/content
sudo install -o root -g wazuh -m 0640 /opt/oci-wazuh-demo/content/decoders/*.xml /var/ossec/etc/decoders/
sudo install -o root -g wazuh -m 0640 /opt/oci-wazuh-demo/content/rules/*.xml /var/ossec/etc/rules/
sudo install -o root -g root -m 0755 /opt/oci-wazuh-demo/content/consumer/oci_log_consumer.py /opt/oci-wazuh-demo/consumer/oci_log_consumer.py
sudo touch /var/ossec/logs/oci/audit.json /var/ossec/logs/oci/flow.json
sudo chown -R wazuh:wazuh /var/ossec/logs/oci
sudo chmod 0750 /var/ossec/logs/oci
sudo chmod 0640 /var/ossec/logs/oci/audit.json /var/ossec/logs/oci/flow.json
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
} > "$evidence"

cat "$evidence"
