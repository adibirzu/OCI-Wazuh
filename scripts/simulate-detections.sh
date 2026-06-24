#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/wazuh-ssh.sh"

mkdir -p "$REPO_ROOT/artifacts/validation"
evidence="$REPO_ROOT/artifacts/validation/M6-M7-simulated-detections.txt"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/oci-wazuh-sim.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
marker="oci-wazuh-demo-${stamp//[:TZ-]/}"

remote_command="set -euo pipefail
marker='$marker'
stamp='$stamp'
sudo mkdir -p /var/ossec/logs/oci
printf '%s\n' '{\"source\":\"audit\",\"time\":\"'$stamp'\",\"eventType\":\"com.oraclecloud.identitycontrolplane.createtagnamespace\",\"principalName\":\"oci-wazuh-demo-user\",\"sourceIp\":\"203.0.113.10\",\"compartmentId\":\"example-compartment\",\"demoMarker\":\"'$marker'\",\"raw\":{\"eventType\":\"com.oraclecloud.identitycontrolplane.createtagnamespace\"}}' | sudo tee -a /var/ossec/logs/oci/audit.json >/dev/null
printf '%s\n' '{\"source\":\"flow\",\"time\":\"'$stamp'\",\"srcaddr\":\"198.51.100.10\",\"dstaddr\":\"198.51.100.20\",\"srcport\":51514,\"dstport\":3389,\"protocol\":6,\"action\":\"REJECT\",\"bytes\":0,\"packets\":3,\"demoMarker\":\"'$marker'\",\"raw\":{\"action\":\"REJECT\"}}' | sudo tee -a /var/ossec/logs/oci/flow.json >/dev/null
sudo chown wazuh:wazuh /var/ossec/logs/oci/audit.json /var/ossec/logs/oci/flow.json
sudo chmod 0640 /var/ossec/logs/oci/audit.json /var/ossec/logs/oci/flow.json
sleep 45
sudo grep \"\$marker\" /var/ossec/logs/alerts/alerts.json | grep -E '\"id\":\"100000\"|\"id\":\"100100\"' | tail -20"

wazuh_ssh "$remote_command" > "$tmpdir/alerts.txt"

grep -q '"id":"100000"' "$tmpdir/alerts.txt"
grep -q '"id":"100100"' "$tmpdir/alerts.txt"

{
  echo "simulated_detections=green"
  echo "audit_rule_100000=green"
  echo "flow_rule_100100=green"
  echo "marker=$marker"
} > "$evidence"

cat "$evidence"
