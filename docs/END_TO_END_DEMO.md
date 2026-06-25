# OCI Wazuh End-to-End Demo Runbook

This is the operator path for deploying the OCI Wazuh demo end to end and showing both:

- Wazuh dashboards with OCI Audit, VCN Flow, Linux FIM/SCA, and GOAD/Windows detections
- OCI Log Analytics dashboards with Wazuh alert data correlated with OCI Audit, VCN Flow, OS, and Sysmon/EDR logs

## 1. Prerequisites

Run from this repository:

```bash
cd /Users/abirzu/dev/OCI-Wazuh
make bootstrap
make cap-preflight
```

Required local tools:

- OCI CLI configured with the target profile
- Terraform
- Python 3
- SSH key pair for deployed Linux hosts
- Ansible for Windows/GOAD reuse

Required OCI state:

- A target compartment
- A public/bastion subnet and workload subnet
- Log Analytics onboarded in the tenancy
- Vault secrets for GOAD/WinRM credentials when using GOAD reuse
- Permission for the Wazuh instance principal to read OCI Audit events
- Either permission to create VCN Flow Logs for the monitored subnet/VCN/VNIC, or an existing Flow Log OCID/log group OCID to reuse

For CAP development, `scripts/cap-up.sh` resolves most values from the local OCI config and writes `terraform/terraform.tfvars`.

For public/standalone use, copy and edit:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Use placeholders only in committed files. Real OCIDs, IPs, and credentials stay in local tfvars, environment variables, or OCI Vault.

If the monitored subnet already has Flow Logs enabled, do not create a duplicate. Set this in local `terraform/terraform.tfvars`:

```hcl
existing_flow_logs = [{
  compartment_id = "<SOURCE_COMPARTMENT_OCID>"
  log_group_id   = "<EXISTING_FLOW_LOG_GROUP_OCID>"
  log_id         = "<EXISTING_FLOW_LOG_OCID>"
}]
```

When `existing_flow_logs` is set, Terraform reuses that Flow Log and creates only the SCH permissions/connector needed to route it to the Wazuh stream.

## 2. Deploy Wazuh and Linux Agents

Development CAP path:

```bash
USE_BASTION_SUBNET_FOR_WORKLOADS=true \
WORKLOAD_ASSIGN_PUBLIC_IP=true \
make up
```

Standalone path after editing `terraform/terraform.tfvars`:

```bash
make up
```

This provisions:

- Wazuh AIO, pinned to Wazuh 4.14.x
- Oracle Linux 9 agent
- Ubuntu 24.04 agent
- OCI NSGs and host firewall rules for dashboard/API/agent enrollment
- Wazuh auth replacement for duplicate disconnected agents

## 3. Validate Wazuh and Linux Detection

Run:

```bash
make e2e
```

Expected green artifacts:

- `artifacts/validation/M3-dashboard.txt`
- `artifacts/validation/M3-wazuh-status.txt`
- `artifacts/validation/M4-agent-control.txt`
- `artifacts/validation/M4-fim-marker-alerts.txt`
- `artifacts/validation/e2e.txt`

The current development path may fall back to direct Wazuh SSH if bastion SSH is rate-limited. This is expected in CAP development and documented in [KB-OCI-WAZUH-RUNBOOK](kb/KB-OCI-WAZUH-RUNBOOK.md).

Dashboard tunnel command:

```bash
terraform -chdir=terraform output -raw wazuh_dashboard_tunnel_command
```

Open the tunnel output in a browser and log in to Wazuh Dashboard.

## 4. Reuse or Install GOAD

Discover existing GOAD first:

```bash
make goad-discover
```

Green output:

```text
goad_vcn=ready
host.braavos=RUNNING
host.castelblack=RUNNING
host.kingslanding=RUNNING
host.meereen=RUNNING
host.winterfell=RUNNING
goad_reuse=ready
```

If GOAD is missing, deploy GOADv3 with the OCI provider, then rerun discovery.

When GOAD is ready, run the Ansible reuse path with an inventory containing:

- `wazuh_manager`
- `goad_hosts`
- `wazuh_manager_ip`
- WinRM credentials from OCI Vault or local environment

Playbook:

```bash
make goad-up
make goad-validate
```

This installs or updates:

- Wazuh Windows agent
- Sysmon using pinned `olafhartong/sysmon-modular`
- SOC Fortress Wazuh rules on the Wazuh manager

Expected validation:

```text
host.kingslanding=Active
host.winterfell=Active
host.castelblack=Active
host.meereen=Active
host.braavos=Active
goad_sysmon_socfortress_alerts=green
```

The GOAD path uses a single SSH tunnel for WinRM to avoid repeated SSH handshakes during deployment. In `auto` mode it discovers the running GOAD jumpbox key from OCI metadata when possible. When direct Wazuh-to-GOAD routing is not possible because OCI local peering is non-transitive or VCN CIDRs overlap, `make goad-up` uses the hub bastion as a persistent 1514/1515 relay and configures Windows agents with the bastion private IP as their Wazuh manager endpoint. `make goad-down` removes the Windows agents, Sysmon, Wazuh manager records, and the bastion relay services/firewall rules.

## 5. Configure Wazuh Alerts into Log Analytics

Run:

```bash
make wazuh-log-analytics
```

Expected output:

```text
wazuh_log_analytics=started
oci_logging_log_group=ready
oci_logging_custom_log=ready
wazuh_dynamic_group=ready
wazuh_logging_policy=ready
wazuh_agent_config=ready
sch_to_log_analytics=ready_or_updating
```

This creates or reconciles:

- OCI Logging log group for Wazuh
- OCI Logging custom log for Wazuh alerts
- Dynamic group scoped to the Wazuh instance
- IAM policy for Wazuh alert log publishing
- Unified Agent configuration tailing `/var/ossec/logs/alerts/alerts.json`
- Log Analytics log group
- SCH connector from Wazuh alert custom log to Log Analytics

Allow several minutes for Dynamic Group and Unified Agent propagation.

## 6. Validate Log Analytics Bridge

Run:

```bash
make log-analytics-bridge
```

Expected green output:

```text
namespace=ready
source.Linux Syslog Logs=ready
source.Linux Secure Logs=ready
source.Windows Security Events=ready
source.Windows System Events=ready
source.Windows Application Events=ready
source.Windows Sysmon Events=ready
source.OCI Audit Logs=ready
source.OCI VCN Flow Unified Schema Logs=ready
entity.oci-wazuh-demo-wazuh-aio=ready
entity.oci-wazuh-demo-ol9-agent=ready
entity.oci-wazuh-demo-ubuntu-agent=ready
entity.braavos=ready
entity.castelblack=ready
entity.kingslanding=ready
entity.meereen=ready
entity.winterfell=ready
log_analytics_bridge=ready
```

## 7. Deploy Wazuh OCI Content and Validate Synthetic OCI Detections

Install or refresh the local OCI decoders, rules, logcollector entries, and the reusable OCI log consumer on the Wazuh manager:

```bash
make wazuh-content
```

Expected green output:

```text
wazuh_content=deployed
oci_decoders=ready
oci_rules=ready
oci_logcollector=ready
consumer=ready
consumer_systemd=ready
```

Run the synthetic OCI Audit and VCN Flow detection gate:

```bash
make simulate-detections
```

Expected green output:

```text
simulated_detections=green
audit_rule_100000=green
flow_rule_100100=green
```

If SSH throttling appears during development validation, run the target with control sockets disabled:

```bash
WAZUH_SSH_CONTROL=none make simulate-detections
```

The synthetic gate appends normalized JSON lines to `/var/ossec/logs/oci/audit.json` and `/var/ossec/logs/oci/flow.json`, then checks Wazuh alerts for rule `100000` and `100100`.

## 8. Validate Real OCI Audit and VCN Flow Logs

Run:

```bash
make validate-real-oci-logs
```

This performs real OCI actions:

- creates and deletes a temporary tag namespace to generate OCI Audit events
- generates denied TCP traffic to a monitored host to produce VCN Flow records
- waits for Wazuh rules `100000` and `100100`

Expected green output:

```text
real_oci_logs=green
audit_rule_100000=green
flow_rule_100100=green
```

The real path is:

- OCI Audit API -> Wazuh Audit consumer -> `/var/ossec/logs/oci/audit.json` -> Wazuh logcollector
- OCI VCN Flow Log -> Service Connector Hub -> OCI Streaming -> Wazuh Flow consumer -> `/var/ossec/logs/oci/flow.json` -> Wazuh logcollector

Allow several minutes for OCI Logging, SCH, Streaming, and Wazuh rule processing. The synthetic gate remains useful for parser/rule regressions, but `make validate-real-oci-logs` is the end-to-end ingestion proof.

## 9. Configure Dedicated OpenSearch Indices and Wazuh Dashboard Objects

The Wazuh detection path still writes normalized OCI telemetry to local files so Wazuh rules can fire. The same consumer can also index those records into dedicated OpenSearch indices:

- `oci-audit-YYYY.MM.dd`
- `oci-flow-YYYY.MM.dd`

Default AIO backend:

```bash
make opensearch-oci
make validate-opensearch-oci
```

Expected green output:

```text
opensearch_oci=green
oci_audit_count=<nonzero>
oci_flow_count=<nonzero>
oci_audit_template=ready
oci_flow_template=ready
dashboard.oci_logs_overview=ready
```

The command creates:

- index templates for `oci-audit-*` and `oci-flow-*`
- OpenSearch Dashboards data views for `oci-audit-*` and `oci-flow-*`
- saved searches `OCI Audit - Latest Events` and `OCI Flow - Denied Traffic`
- dashboard `OCI Logs Overview`

For OCI Search Service with OpenSearch, choose one of two paths:

- Existing cluster: export `OCI_WAZUH_OPENSEARCH_BACKEND=oci_opensearch`, `OCI_WAZUH_OPENSEARCH_URL`, `OCI_WAZUH_DASHBOARD_URL`, `OCI_WAZUH_OPENSEARCH_USERNAME`, and `OCI_WAZUH_OPENSEARCH_PASSWORD`, then run `make opensearch-oci`.
- Managed by this repo: set `create_oci_opensearch = true`, a stable `oci_opensearch_master_password_hash`, and the runtime `oci_opensearch_master_password` in local `terraform/terraform.tfvars`, run `make up`, then run `OCI_WAZUH_OPENSEARCH_BACKEND=oci_opensearch make opensearch-oci`.

Do not use `wazuh-alerts-*` for raw OCI Audit and Flow exploration. Use `wazuh-alerts-*` for Wazuh detections and `oci-audit-*` / `oci-flow-*` for the normalized OCI source records.

## 10. Build OCI Log Analytics Dashboard

Open OCI Console:

```text
Observability & Management > Log Analytics > Log Explorer
```

Start with source inventory:

```text
* | stats count by "Log Source" | sort -count
```

Then create saved searches from:

```text
dashboards/log-analytics/oci-wazuh-dashboard-queries.json
```

Recommended dashboard panels:

| Panel | Query ID |
|---|---|
| Telemetry Source Inventory | `source_inventory` |
| VCN Flow Actions | `vcn_flow_actions` |
| VCN Rejects by Source and Destination | `vcn_rejects_by_pair` |
| OCI Audit Events by Type | `oci_audit_events` |
| OCI Audit Events by User and Source | `oci_audit_users` |
| GOAD Sysmon Event IDs | `windows_sysmon_event_ids` |
| GOAD Sysmon Network Connections | `windows_sysmon_network` |
| Linux Host Logs by Source | `linux_host_logs` |
| Wazuh Alert Volume | `wazuh_alert_volume` |
| Wazuh Alerts Raw Search | `wazuh_alert_raw_search` |

If Wazuh alert queries return zero rows immediately after configuration, wait for OCI Unified Agent and SCH propagation, then generate a Wazuh alert with `make e2e`.

## 11. Build Wazuh Dashboard Views

Open Wazuh Dashboard through the SSH tunnel.

Use these data views:

```text
Name: OCI Wazuh Alerts
Index pattern: wazuh-alerts-*
Time field: timestamp

Name: OCI Audit Raw
Index pattern: oci-audit-*
Time field: @timestamp

Name: OCI Flow Raw
Index pattern: oci-flow-*
Time field: @timestamp
```

If `make opensearch-oci` has already run, the `oci-audit-*` and `oci-flow-*` data views and `OCI Logs Overview` dashboard are created automatically.

Create saved searches and dashboard panels from:

```text
dashboards/wazuh/oci-wazuh-views.md
```

Required Wazuh views:

- OCI Audit Detections: rule IDs `100000-100099`
- VCN Flow Detections: rule IDs `100100-100199`
- Linux FIM and SCA
- GOAD Windows and Sysmon
- MITRE technique rollup

## 12. Generate Demo Events

Linux FIM:

```bash
make e2e
```

GOAD/Sysmon:

- Trigger a benign failed logon on a GOAD host.
- Confirm Windows Security/Sysmon events in Log Analytics.
- Confirm Wazuh Windows agent alerting once the GOAD playbook has enrolled hosts.

OCI Audit:

```bash
oci iam tag-namespace create \
  --compartment-id "$COMPARTMENT_OCID" \
  --name "wazuhDemoTemp" \
  --description "temporary Wazuh audit demo"
```

Delete the namespace after the alert is observed.

VCN Flow reject:

- Generate denied traffic to a closed port on a monitored host.
- Confirm VCN flow `reject` rows in Log Analytics.
- Confirm Wazuh rule `100100` after OCI flow ingestion is active.

Synthetic OCI Audit and VCN Flow:

```bash
make simulate-detections
```

This is the fastest deterministic way to prove the Wazuh content path before waiting for live OCI Audit or VCN Flow delivery.

Real OCI Audit and VCN Flow:

```bash
make validate-real-oci-logs
```

Use this for the live demo proof that the deployment is ingesting real OCI telemetry from the target tenancy.

## 13. Demo Flow

1. Show Wazuh manager status and active Linux agents.
2. Show Linux FIM alert from `make e2e`.
3. Show GOAD hosts active and Sysmon/SOC Fortress alerting with `make goad-validate`.
4. Show Log Analytics bridge green with `make log-analytics-bridge`.
5. Show OCI parser/rule content green with `make simulate-detections`.
6. Show real OCI ingestion green with `make validate-real-oci-logs`.
7. Show dedicated OpenSearch indices green with `make validate-opensearch-oci`.
8. In OCI Log Analytics, open the source inventory and dashboard panels.
9. In Wazuh Dashboard, open `OCI Logs Overview`, OCI Audit, VCN Flow, Linux FIM, and GOAD/Sysmon views.
10. Trigger one benign event per telemetry family and show it in both systems where applicable.

## 14. Teardown

Destroy standalone lab resources:

```bash
make down
```

`make down` first runs GOAD cleanup. For reused GOAD hosts it removes Wazuh Windows agents, Sysmon, staging directories, and Wazuh manager agent records, then Terraform destroys demo-owned resources. For shared GOAD and OCI-DEMO resources, do not destroy the shared GOAD VCN or shared OCI-DEMO Log Analytics content unless the parent deployment owns them. The Wazuh-specific resources created by this repo are tagged or named with the project prefix.

Post-destroy check:

```bash
oci search resource structured-search \
  --query-text "query all resources where freeformTags.project = 'oci-wazuh-demo'"
```

Expected result: no Wazuh-owned residual resources.
