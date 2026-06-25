# OCI Wazuh and Log Analytics Architecture

This page defines the publishable architecture and workflows for the OCI Wazuh detection lab. It intentionally avoids real tenancy identifiers, IP addresses, credentials, and internal-only topology.

## System Context

```mermaid
flowchart LR
  Operator[Operator workstation] -->|SSH tunnel| Bastion[Bastion]
  Bastion -->|443 tunnel| Wazuh[Wazuh AIO]
  Wazuh -->|OpenSearch local or OCI Search with OpenSearch| Search[(OpenSearch)]
  Linux1[Oracle Linux 9 agent] -->|1514/1515| Wazuh
  Linux2[Ubuntu 24.04 agent] -->|1514/1515| Wazuh
  GOAD[GOAD or Windows Server agents] -->|Wazuh agent + Sysmon| Wazuh
  OCI[OCI Audit and VCN Flow Logs] --> Wazuh
  Wazuh -->|alerts.json via Unified Agent and Connector Hub| LA[OCI Log Analytics]
  OCI -->|OCI Logging sources| LA
```

## OCI Network Topology

```mermaid
flowchart TB
  subgraph VCN["OCI Wazuh VCN"]
    subgraph Public["public subnet"]
      Bastion["bastion / SSH tunnel"]
    end
    subgraph Private["private workload subnet"]
      Wazuh["Wazuh all-in-one"]
      OL9["Oracle Linux 9 agent"]
      Ubuntu["Ubuntu 24.04 agent"]
      OptionalWin["optional Windows Server 2022"]
    end
  end

  subgraph Shared["optional reused GOAD VCN"]
    Braavos[braavos]
    Castelblack[castelblack]
    Kingslanding[kingslanding]
    Meereen[meereen]
    Winterfell[winterfell]
  end

  Bastion --> Wazuh
  OL9 --> Wazuh
  Ubuntu --> Wazuh
  OptionalWin --> Wazuh
  Shared -->|VCN peering or bastion relay| Wazuh
```

## Telemetry Ingestion Workflow

```mermaid
flowchart LR
  Audit[OCI Audit API] --> AuditConsumer[Wazuh OCI Audit consumer]
  Flow[VCN Flow Logs] --> Logging[OCI Logging]
  Logging --> SCH[Connector Hub]
  SCH --> Stream[OCI Streaming]
  Stream --> FlowConsumer[Wazuh Flow consumer]

  AuditConsumer --> AuditFile[/var/ossec/logs/oci/audit.json]
  FlowConsumer --> FlowFile[/var/ossec/logs/oci/flow.json]

  AuditFile --> Logcollector[Wazuh logcollector]
  FlowFile --> Logcollector
  Logcollector --> Rules[Custom decoders and rules 100000+]
  Rules --> Alerts[wazuh-alerts-*]
```

## OpenSearch Data Model

```mermaid
flowchart TB
  WazuhRules[Wazuh detections] --> WazuhAlerts["wazuh-alerts-*"]
  AuditConsumer[Audit consumer] --> AuditIndex["oci-audit-*"]
  FlowConsumer[Flow consumer] --> FlowIndex["oci-flow-*"]

  WazuhAlerts --> DetectionViews[Detection views and MITRE rollups]
  AuditIndex --> AuditViews[Raw OCI Audit searches]
  FlowIndex --> FlowViews[Raw VCN Flow searches]
```

Use `wazuh-alerts-*` for detections. Use `oci-audit-*` and `oci-flow-*` for normalized raw OCI source records.

## Log Analytics Correlation Workflow

```mermaid
flowchart LR
  WazuhAlertsFile[/var/ossec/logs/alerts/alerts.json] --> UnifiedAgent[OCI Unified Agent]
  UnifiedAgent --> OCILogging[OCI Logging custom log]
  OCILogging --> SCH[Connector Hub]
  SCH --> LA[OCI Log Analytics]

  AuditLogs[OCI Audit Logs] --> LA
  FlowLogs[OCI VCN Flow Unified Schema Logs] --> LA
  LinuxLogs[Linux Syslog and Secure Logs] --> LA
  WindowsLogs[Windows Security and Sysmon Events] --> LA

  LA --> Dashboard[Correlation dashboards]
  Dashboard --> Backlog[Security posture backlog]
```

## Teaching and Screenshot Publishing Workflow

```mermaid
flowchart LR
  Lessons[HTML lessons] --> StaticScreens[Public-safe lesson screenshots]
  AuthChrome[Authenticated Chrome session] --> RawLive[Ignored raw screenshots]
  RawLive --> Sanitizer[Sanitizer script]
  Sanitizer --> SafeLive[Sanitized Wazuh and Log Analytics screenshots]
  StaticScreens --> Wiki[Teaching wiki]
  SafeLive --> Wiki
  Wiki --> Validate[make teach-validate]
```

Raw authenticated screenshots live under `docs/wiki/assets/live/` and are ignored by Git. Only sanitized screenshots should be committed.

## Validation Workflow

```mermaid
flowchart TB
  Bootstrap[make bootstrap] --> Deploy[make up]
  Deploy --> Linux[make e2e]
  Deploy --> GOAD[make goad-up and make goad-validate]
  Deploy --> Content[make wazuh-content]
  Content --> Synthetic[make simulate-detections]
  Content --> RealOCI[make validate-real-oci-logs]
  RealOCI --> OpenSearch[make opensearch-oci and validate-opensearch-oci]
  Deploy --> LogAnalytics[make wazuh-log-analytics and make log-analytics-bridge]
  LogAnalytics --> Demo[Wazuh and Log Analytics demo]
  Demo --> Down[make down]
```

## Teardown Workflow

```mermaid
flowchart LR
  Start[make down] --> GOADCleanup[Remove Wazuh agent and Sysmon from reused GOAD hosts]
  GOADCleanup --> ManagerCleanup[Remove GOAD agent records from Wazuh manager]
  ManagerCleanup --> TerraformDestroy[terraform destroy demo-owned OCI resources]
  TerraformDestroy --> Search[OCI resource search by project tag]
  Search --> Empty[No residual demo-owned resources]
```

## Security Boundaries

- No dashboard is intentionally exposed to the public internet.
- Wazuh Dashboard access should use an SSH tunnel.
- OCI identifiers, credentials, internal IPs, and authenticated raw screenshots must not be committed.
- Public docs use placeholders and sanitized screenshots.
- `make teach-validate` checks required teaching assets, local links, ignored raw-auth paths, and redaction-sensitive patterns.

## Primary References

- [End-to-end demo runbook](../END_TO_END_DEMO.md)
- [Ingestion KB](../kb/KB-OCI-WAZUH-INGESTION.md)
- [Runbook KB](../kb/KB-OCI-WAZUH-RUNBOOK.md)
- [Teaching module index](WAZUH_LOG_ANALYTICS_MODULE_INDEX.md)
