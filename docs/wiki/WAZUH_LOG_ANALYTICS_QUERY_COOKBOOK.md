# Wazuh and OCI Log Analytics Query Cookbook

Use this cookbook when building dashboard widgets or teaching investigations. Source names and fields can differ by tenancy, so always run source inventory first.

## Source Inventory

```text
* | stats count by "Log Source" | sort -count
```

Use this before every new dashboard, workshop, or customer deployment.

## Log Analytics Queries

| Query | Purpose | OCL |
|---|---|---|
| Telemetry source inventory | Confirm source names and volumes | `* | stats count by "Log Source" | sort -count` |
| VCN flow actions | Compare accepted and rejected flows | `'Log Source' = 'OCI VCN Flow Unified Schema Logs' | stats count by Action | sort -count` |
| VCN rejects by pair | Identify scan-like denied traffic | `'Log Source' = 'OCI VCN Flow Unified Schema Logs' and Action = 'reject' | stats count by 'Source IP', 'Destination IP', 'Destination Port' | sort -count` |
| OCI Audit by event type | Find active cloud-control actions | `'Log Source' = 'OCI Audit Logs' | stats count by 'Event Type' | sort -count` |
| OCI Audit by user/source | Identify identity and source combinations | `'Log Source' = 'OCI Audit Logs' | stats count by 'User Name', 'Source IP', 'Event Type' | sort -count` |
| GOAD Sysmon event IDs | Find Windows event mix | `'Log Source' = 'Windows Sysmon Events' | stats count by 'Event ID' | sort -count` |
| GOAD Sysmon network | Find host/process egress patterns | `'Log Source' = 'Windows Sysmon Events' and 'Event ID' = '3' | stats count by 'Host Name', 'Process Name', 'Destination IP' | sort -count` |
| Linux host source mix | Confirm Linux source coverage | `'Log Source' in ('Linux Syslog Logs','Linux Secure Logs') | stats count by 'Log Source' | sort -count` |
| Wazuh alert volume | Confirm Wazuh alerts reached Log Analytics | `'Log Source' = 'oci-wazuh-demo-wazuh-alerts' | stats count as WazuhAlerts` |
| Wazuh raw alert search | Inspect recent Wazuh alert payloads | `'Log Source' = 'oci-wazuh-demo-wazuh-alerts' | sort -Time | head 50` |

## Wazuh KQL Filters

| View | KQL |
|---|---|
| OCI Audit detections | `rule.id >= 100000 and rule.id <= 100099` |
| VCN Flow detections | `rule.id >= 100100 and rule.id <= 100199` |
| All OCI detections | `rule.id >= 100000 and rule.id <= 100199` |
| Linux FIM and SCA | `rule.groups: syscheck or rule.groups: sca` |
| GOAD Windows and Sysmon | `agent.name: (braavos or castelblack or kingslanding or meereen or winterfell) or rule.groups: windows` |
| MITRE technique rollup | `rule.mitre.id: *` |

## Correlation Recipes

| Question | Wazuh starting point | Log Analytics pivot | Posture output |
|---|---|---|---|
| Who changed cloud resources from an unusual source? | OCI Audit rule `100000` | Audit by user/source | IAM review or MFA enforcement |
| Which denied traffic should we investigate? | VCN Flow rule `100100` | VCN rejects by pair | NSG change, scanner validation, or exposure review |
| Which host changed unexpectedly? | Linux FIM alert | Linux secure/syslog for same entity | Baseline update or change-control review |
| Which Windows process created network traffic? | Sysmon alert | Sysmon network query | Segmentation or endpoint containment decision |
| Which detections have no owner? | High-severity Wazuh alerts | Wazuh alert volume and raw search | Posture backlog ownership item |

## Query Hygiene

- Quote Log Analytics field names that contain spaces.
- Keep the source inventory widget visible on every dashboard.
- Save source-family widgets before correlation widgets.
- Name widgets after the security question they answer.
- Attach each dashboard row to a runbook or posture backlog process.
