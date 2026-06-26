# Wazuh and OCI Log Analytics Glossary and FAQ

Use this page when teaching or onboarding new users. It defines the terms used in the lab and answers common questions that come up during deployment, demos, and workshops.

## Glossary

| Term | Meaning in this project |
|---|---|
| Wazuh manager | The Wazuh component that receives agent events, applies rules, and manages agents. |
| Wazuh indexer | The OpenSearch-based storage layer used by Wazuh. |
| Wazuh Dashboard | The web interface for Wazuh alerts, data views, and saved objects. |
| Agent enrollment | The process that registers a host with Wazuh so it can send events. |
| FIM | File Integrity Monitoring. It detects file changes on monitored hosts. |
| SCA | Security Configuration Assessment. It checks hosts against hardening policies. |
| Syscollector | Wazuh inventory collection for packages, processes, ports, hardware, and OS data. |
| Vulnerability detection | Wazuh capability that maps host inventory to known vulnerabilities. |
| Sysmon | Windows system monitor that generates detailed process, network, and registry events. |
| SOC Fortress rules | Community Wazuh rules commonly used to improve Windows and Sysmon detection coverage. |
| GOAD | Game of Active Directory, an AD lab that can be reused as Windows detection telemetry. |
| OCI Audit | OCI control-plane event source showing API actions, actors, targets, and metadata. |
| VCN Flow Logs | OCI network telemetry showing accepted and rejected flows. |
| Connector Hub | OCI service that routes logs between OCI services such as Logging, Streaming, Object Storage, and Log Analytics. |
| OCI Streaming | Streaming service used as the primary VCN Flow delivery path in this lab. |
| OCI Log Analytics | OCI analytics service used for cross-source search, dashboards, and correlation. |
| OpenSearch data view | A dashboard search pattern such as `wazuh-alerts-*`, `oci-audit-*`, or `oci-flow-*`. |
| Raw source record | A normalized record from OCI Audit or VCN Flow before it becomes a Wazuh alert. |
| Detection alert | A Wazuh rule result with severity, rule ID, groups, and optional MITRE mapping. |
| Teardown | The process that removes demo-owned OCI resources and demo-installed agents from reused hosts. |

## FAQ

### Is this only a Wazuh deployment?

No. The lab combines deployment, endpoint telemetry, OCI service logs, Wazuh detections, OpenSearch views, Log Analytics correlation, validation gates, teardown, and teaching material.

### Why use both Wazuh and OCI Log Analytics?

Wazuh is the detection and endpoint workbench. OCI Log Analytics is the cross-source correlation and enterprise dashboard layer. Using both lets teams keep Wazuh rule context while still searching across OCI service logs, OS logs, Windows events, Sysmon, and Wazuh alerts.

### Why keep raw OCI records in dedicated indices?

Raw OCI records answer source-data questions. Wazuh alerts answer detection questions. Keeping `oci-audit-*` and `oci-flow-*` separate from `wazuh-alerts-*` avoids confusing source fields with rule fields.

### Which ingestion mode should I choose first?

Use Streaming for the primary VCN Flow path when permissions allow it. Use Object Storage when bucket delivery is easier to approve. Use direct API for Audit-focused validation and restricted development. Use the Log Analytics bridge when enterprise correlation is part of the demo.

### Can this run in any tenancy?

The public design is parameterized for reuse in any tenancy, but each tenancy must provide permissions, region selection, compartment scope, network access, and required service availability. Do not commit tenancy-specific values.

### Is GOAD required?

No. GOAD is the default reuse path when reachable because it provides rich Windows and AD telemetry. If GOAD is absent or not reachable, the Windows path can be skipped or implemented with a new Windows Server host, depending on the chosen deployment mode.

### What proves real OCI logs are flowing?

`make validate-real-oci-logs` is the key proof. It should confirm real OCI Audit activity and VCN Flow activity are visible through the ingestion path and parsed into Wazuh.

### What proves the demo can be cleaned up?

`make down` should remove demo-owned OCI resources and clean Wazuh agents/Sysmon from reused GOAD hosts when the demo installed them. A post-destroy resource search by project tag should be empty for demo-owned resources.

### Why are screenshots sanitized?

Authenticated screenshots can contain usernames, hostnames, source addresses, counts, tenancy structure, or other operational details. Public docs should show workflow and UI shape without exposing real environment data.

### Why does the wiki use placeholders?

Placeholders make examples reusable and prevent accidental exposure. Use values such as `<TENANCY_OCID>`, `<COMPARTMENT_OCID>`, `<PRIVATE_IP>`, `<WAZUH_URL>`, and `<SECRET_NAME>` in shared material.

### What should a dashboard widget answer?

Each widget should answer one security question. Examples: "Which sources are present?", "Which flows were rejected?", "Which user performed a privileged action?", or "Which Wazuh alerts increased this week?"

### How do I know a learner is ready?

Use the skill ladder and learner workbook. A ready learner can identify sources, explain one Wazuh alert, find the raw OCI record, correlate it in Log Analytics, and convert the evidence into a posture action.

### What should become a production pilot?

Promote only the parts that have clear owners, stable ingestion, approved retention, access control, cost model, validation gates, and an operating cadence.

## Troubleshooting Questions

| Symptom | First question | First action |
|---|---|---|
| Dashboard is empty | Are the expected sources present? | Run Log Analytics source inventory |
| Wazuh widgets are empty | Are Wazuh alerts classified as OCI Unified Schema? | Filter `OCI Unified Schema Logs` with `wazuh-alerts-json` |
| Dashboard reports busy, unavailable, or incomplete results | Is ingestion fresh but the query too broad? | Run `make log-analytics-freshness`, reduce time range, add source filters |
| Wazuh alert missing | Did the raw record arrive? | Check `oci-audit-*` or `oci-flow-*` |
| Raw record missing | Did delivery complete? | Check Connector Hub, Streaming, bucket, or API path |
| Windows host missing | Is agent enrollment complete? | Check Wazuh agent status and GOAD connectivity |
| Flow detection missing | Was reject traffic generated? | Confirm flow log fields and time window |
| Teardown incomplete | Is the resource demo-owned or shared? | Check tags and GOAD cleanup output |

## Related Pages

- [Adoption guide](WAZUH_LOG_ANALYTICS_ADOPTION_GUIDE.md)
- [Learning curve and role paths](WAZUH_LOG_ANALYTICS_LEARNING_CURVE.md)
- [Learner workbook](WAZUH_LOG_ANALYTICS_LEARNER_WORKBOOK.md)
- [Product capabilities](WAZUH_LOG_ANALYTICS_PRODUCT_CAPABILITIES.md)
- [Architecture and workflows](WAZUH_LOG_ANALYTICS_ARCHITECTURE.md)
