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

For CAP development, `scripts/cap-up.sh` resolves most values from the local OCI config and writes `terraform/terraform.tfvars`.

For public/standalone use, copy and edit:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Use placeholders only in committed files. Real OCIDs, IPs, and credentials stay in local tfvars, environment variables, or OCI Vault.

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
ansible-playbook -i ansible/inventory/<inventory>.yml ansible/playbooks/goad-reuse.yml
```

This installs or updates:

- Wazuh Windows agent
- Sysmon using pinned `olafhartong/sysmon-modular`
- SOC Fortress Wazuh rules on the Wazuh manager

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

## 8. Build OCI Log Analytics Dashboard

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

## 9. Build Wazuh Dashboard Views

Open Wazuh Dashboard through the SSH tunnel.

Create data view:

```text
Name: OCI Wazuh Alerts
Index pattern: wazuh-alerts-*
Time field: timestamp
```

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

## 10. Generate Demo Events

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

## 11. Demo Flow

1. Show Wazuh manager status and active Linux agents.
2. Show Linux FIM alert from `make e2e`.
3. Show GOAD hosts running with `make goad-discover`.
4. Show Log Analytics bridge green with `make log-analytics-bridge`.
5. Show OCI rules green with `make simulate-detections`.
6. In OCI Log Analytics, open the source inventory and dashboard panels.
7. In Wazuh Dashboard, open OCI Audit, VCN Flow, Linux FIM, and GOAD/Sysmon views.
8. Trigger one benign event per telemetry family and show it in both systems where applicable.

## 12. Teardown

Destroy standalone lab resources:

```bash
make down
```

For shared GOAD and OCI-DEMO resources, do not destroy the shared GOAD VCN or shared OCI-DEMO Log Analytics content unless the parent deployment owns them. The Wazuh-specific resources created by this repo are tagged or named with the project prefix.

Post-destroy check:

```bash
oci search resource structured-search \
  --query-text "query all resources where freeformTags.project = 'oci-wazuh-demo'"
```

Expected result: no Wazuh-owned residual resources.
