#!/usr/bin/env bash
set -euo pipefail

mode="${1:-up}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tfvars="${TFVARS_FILE:-$repo_root/terraform/terraform.tfvars}"
artifacts_dir="$repo_root/artifacts/validation"
mkdir -p "$artifacts_dir"

tfvar_value() {
  local key="$1"
  [[ -f "$tfvars" ]] || return 0
  awk -F= -v k="$key" '$1 ~ "^[[:space:]]*" k "[[:space:]]*$" {gsub(/[ \"]/,"",$2); print $2; exit}' "$tfvars"
}

profile="${OCI_PROFILE:-${OCI_CLI_PROFILE:-$(tfvar_value oci_config_profile)}}"
region="${OCI_REGION:-$(tfvar_value region)}"
project="${PROJECT_NAME:-$(tfvar_value project_name)}"
project="${project:-oci-wazuh-demo}"

if [[ ! -f "$artifacts_dir/M5-goad-discovery-raw.json" ]]; then
  "$repo_root/scripts/goad-discover.sh" >/dev/null
fi

python3 - "$mode" "$profile" "$region" "$project" "$tfvars" "$artifacts_dir/M5-goad-discovery-raw.json" "$artifacts_dir/M5-goad-peering.txt" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

mode, profile, region, project, tfvars_path, discovery_path, evidence_path = sys.argv[1:8]

def tfvar_value(key: str) -> str:
    for line in Path(tfvars_path).read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        left, right = line.split("=", 1)
        if left.strip() == key:
            return right.strip().strip('"')
    return ""

def oci(*args, raw=False):
    cmd = ["oci", "--profile", profile or "DEFAULT"]
    if region:
        cmd.extend(["--region", region])
    cmd.extend(args)
    out = subprocess.check_output(cmd, text=True)
    if raw:
        return out.strip()
    if not out.strip():
        return {}
    return json.loads(out)

def first_goad_instance_id() -> str:
    with open(discovery_path, encoding="utf-8") as fh:
        data = json.load(fh)
    for comp in data.get("compartments", []):
        for inst in comp.get("instances", []):
            if (inst.get("display-name") or "").lower() == "kingslanding":
                return inst["id"]
    raise SystemExit("could not resolve GOAD kingslanding instance for subnet discovery")

def subnet(subnet_id):
    return oci("network", "subnet", "get", "--subnet-id", subnet_id)["data"]

def vcn(vcn_id):
    return oci("network", "vcn", "get", "--vcn-id", vcn_id)["data"]

def list_lpgs(compartment_id, vcn_id):
    return oci(
        "network", "local-peering-gateway", "list",
        "--compartment-id", compartment_id,
        "--vcn-id", vcn_id,
        "--all",
    ).get("data", [])

def find_lpg(compartment_id, vcn_id, display_name):
    for item in list_lpgs(compartment_id, vcn_id):
        if item.get("display-name") == display_name and item.get("lifecycle-state") != "TERMINATED":
            return item
    return None

def create_lpg(compartment_id, vcn_id, display_name):
    existing = find_lpg(compartment_id, vcn_id, display_name)
    if existing:
        return existing
    return oci(
        "network", "local-peering-gateway", "create",
        "--compartment-id", compartment_id,
        "--vcn-id", vcn_id,
        "--display-name", display_name,
        "--freeform-tags", json.dumps({"project": project, "component": "wazuh-detection-lab", "role": "goad-peering"}),
        "--wait-for-state", "AVAILABLE",
    )["data"]

def route_table(rt_id):
    return oci("network", "route-table", "get", "--rt-id", rt_id)["data"]

def normalize_rule(rule):
    return {
        "cidrBlock": rule.get("cidr-block"),
        "description": rule.get("description"),
        "destination": rule.get("destination"),
        "destinationType": rule.get("destination-type"),
        "networkEntityId": rule.get("network-entity-id"),
        "routeType": rule.get("route-type"),
    }

def compact_rule(rule):
    return {k: v for k, v in rule.items() if v not in (None, "")}

def update_routes(rt_id, rules):
    oci(
        "network", "route-table", "update",
        "--rt-id", rt_id,
        "--route-rules", json.dumps([compact_rule(r) for r in rules]),
        "--force",
    )

def ensure_route(rt_id, destination, lpg_id, description):
    rt = route_table(rt_id)
    rules = [normalize_rule(r) for r in rt.get("route-rules", [])]
    for rule in rules:
        if rule.get("destination") == destination and rule.get("networkEntityId") == lpg_id:
            return False
    rules = [r for r in rules if not (r.get("destination") == destination and "oci-wazuh-demo direct GOAD peering" in (r.get("description") or ""))]
    rules.append({
        "destination": destination,
        "destinationType": "CIDR_BLOCK",
        "networkEntityId": lpg_id,
        "description": description,
    })
    update_routes(rt_id, rules)
    return True

def remove_route(rt_id, destination, lpg_id):
    rt = route_table(rt_id)
    rules = [normalize_rule(r) for r in rt.get("route-rules", [])]
    kept = [
        r for r in rules
        if not (r.get("destination") == destination and r.get("networkEntityId") == lpg_id)
    ]
    if len(kept) == len(rules):
        return False
    update_routes(rt_id, kept)
    return True

def delete_lpg(lpg):
    if not lpg:
        return False
    oci(
        "network", "local-peering-gateway", "delete",
        "--local-peering-gateway-id", lpg["id"],
        "--force",
    )
    return True

workload_subnet = subnet(tfvar_value("agent_subnet_id"))
workload_vcn = vcn(workload_subnet["vcn-id"])
goad_vnic = oci("compute", "instance", "list-vnics", "--instance-id", first_goad_instance_id())["data"][0]
goad_subnet = subnet(goad_vnic["subnet-id"])
goad_vcn = vcn(goad_subnet["vcn-id"])

left_name = f"{project}-cyberrange-to-goad"
right_name = f"{project}-goad-to-cyberrange"
left = find_lpg(workload_vcn["compartment-id"], workload_vcn["id"], left_name)
right = find_lpg(goad_vcn["compartment-id"], goad_vcn["id"], right_name)

events = []
if mode == "up":
    left = create_lpg(workload_vcn["compartment-id"], workload_vcn["id"], left_name)
    right = create_lpg(goad_vcn["compartment-id"], goad_vcn["id"], right_name)
    if left.get("peering-status") != "PEERED":
        oci(
            "network", "local-peering-gateway", "connect",
            "--local-peering-gateway-id", left["id"],
            "--peer-id", right["id"],
        )
        events.append("lpg=connected")
    else:
        events.append("lpg=already_connected")
    if ensure_route(workload_subnet["route-table-id"], goad_vcn["cidr-block"], left["id"], "oci-wazuh-demo direct GOAD peering to GOAD"):
        events.append("workload_route=added")
    else:
        events.append("workload_route=present")
    if ensure_route(goad_subnet["route-table-id"], workload_vcn["cidr-block"], right["id"], "oci-wazuh-demo direct GOAD peering to Wazuh"):
        events.append("goad_route=added")
    else:
        events.append("goad_route=present")
elif mode == "down":
    if left:
        events.append("workload_route=removed" if remove_route(workload_subnet["route-table-id"], goad_vcn["cidr-block"], left["id"]) else "workload_route=absent")
    if right:
        events.append("goad_route=removed" if remove_route(goad_subnet["route-table-id"], workload_vcn["cidr-block"], right["id"]) else "goad_route=absent")
    events.append("left_lpg=deleted" if delete_lpg(left) else "left_lpg=absent")
    events.append("right_lpg=deleted" if delete_lpg(right) else "right_lpg=absent")
else:
    raise SystemExit("usage: goad-peering.sh {up|down}")

with open(evidence_path, "w", encoding="utf-8") as fh:
    fh.write(f"goad_peering={mode}\n")
    for event in events:
        fh.write(event + "\n")
print(f"goad_peering={mode}")
for event in events:
    print(event)
PY
