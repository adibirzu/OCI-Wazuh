# Wazuh and OCI Log Analytics Participant Handout

Use this during a workshop or customer demo. It is the short version of the full teaching wiki.

## Mental Model

- Wazuh detects and triages endpoint, cloud, and custom-rule security events.
- OCI Log Analytics correlates Wazuh alerts with OCI Audit, VCN Flow, OS, Windows, and Sysmon telemetry.
- OpenSearch data views separate detections from raw source records:
  - `wazuh-alerts-*` for Wazuh detections
  - `oci-audit-*` for raw normalized OCI Audit records
  - `oci-flow-*` for raw normalized VCN Flow records

## Commands to Remember

```bash
make e2e
make goad-validate
make wazuh-content
make validate-real-oci-logs
make validate-opensearch-oci
make log-analytics-bridge
make dashboards-validate
make teach-validate
make down
```

## First Log Analytics Query

Always run source inventory first:

```text
* | stats count by "Log Source" | sort -count
```

Do not assume source names match another tenancy.

## First Wazuh Filters

```text
rule.id >= 100000 and rule.id <= 100199
rule.groups: syscheck or rule.groups: sca
agent.name: (braavos or castelblack or kingslanding or meereen or winterfell) or rule.groups: windows
```

## Investigation Note Template

```text
Signal:
Source:
Entity or identity:
Network tuple:
Supporting source:
Decision: tune | investigate | harden | accept
Verification query:
```

## Posture Backlog Template

```text
Title:
Control category:
Evidence:
Wazuh view or rule:
Log Analytics query:
Owner:
Action:
Verification query:
Closure evidence:
```

## Completion Checklist

- I can explain why Wazuh and Log Analytics are complementary.
- I can find Wazuh alerts and raw OCI source records.
- I can run source inventory before building dashboards.
- I can pivot from one alert to at least one supporting source.
- I can turn a detection into a posture backlog item with verification.
- I know that `make down` cleans reused-host agents first and deletes only guarded demo-owned resources.
