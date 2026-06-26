# Wazuh and OCI Log Analytics Adoption Guide

This guide helps a team move from a successful demo to a controlled pilot. It focuses on decisions, prerequisites, ownership, and exit criteria rather than implementation details.

## Adoption Stages

| Stage | Goal | Main owner | Exit criteria |
|---|---|---|---|
| 1. Demo | Prove the storyline works end to end. | Demo owner | Wazuh, OCI logs, dashboards, and teardown validated |
| 2. Team workshop | Teach analysts and engineers the workflow. | Security enablement | Workbook completed by target users |
| 3. Pilot | Monitor a limited set of real assets. | Security engineering | Sources, retention, RBAC, and alert workflow approved |
| 4. Production design | Convert pilot lessons into a governed service. | Platform and security architecture | Architecture, cost, support, and risk acceptance documented |
| 5. Operated service | Run detections and dashboards with ownership. | SOC and platform operations | SLAs, runbooks, tuning loop, and reporting cadence active |

## Readiness Checklist

| Area | Question | Ready when |
|---|---|---|
| Tenancy access | Can the deployer create or reuse the required OCI resources? | Permissions are documented and scoped |
| Network path | Can agents reach Wazuh enrollment and manager ports? | `1514` and `1515` paths are validated |
| Console access | Can operators reach Wazuh Dashboard safely? | SSH tunnel path is documented |
| Log sources | Are Audit, Flow, OS, Windows, Sysmon, and Wazuh alert sources expected? | Source inventory lists expected families |
| Secrets | Where are passwords and keys stored? | OCI Vault or local secret path is defined |
| Cost | Who approves compute, storage, Streaming, and Log Analytics spend? | Cost estimate and owner are recorded |
| Teardown | Which resources are demo-owned versus shared? | `make down` behavior is reviewed |
| Data handling | Can logs contain user, host, or network identifiers? | Redaction and retention rules are approved |

## Decision Record Template

```text
Decision:
Context:
Chosen option:
Alternatives considered:
Security impact:
Cost impact:
Teardown impact:
Owner:
Review date:
```

Use this for Windows path, ingestion mode, OpenSearch backend, Log Analytics onboarding, GOAD reuse, and production-pilot scope.

## Adoption Decision Matrix

| Decision | Default | Choose another option when |
|---|---|---|
| Windows path | Reuse GOAD if reachable | The user needs isolated Windows Server 2022 hosts |
| Ingestion path | Streaming for VCN Flow, API for Audit | Object Storage is easier to approve or Streaming is unavailable |
| OpenSearch backend | Wazuh all-in-one indexer | OCI Search with OpenSearch is required for managed service separation |
| Log Analytics bridge | Enabled for demos with enterprise correlation | Log Analytics is not onboarded or not in scope |
| Teardown mode | Remove demo resources and demo-installed agents | A shared environment has explicit retain requirements |

## Pilot Scope

Keep the first pilot narrow.

Recommended first scope:

- one compartment,
- one VCN or workload subnet,
- two Linux hosts,
- one Windows or GOAD path,
- OCI Audit,
- VCN Flow Logs,
- Wazuh alerts into Log Analytics,
- three to five named detections,
- one dashboard page,
- one weekly posture review.

Avoid starting with every compartment, every subnet, and every OCI service log family. Broad scope makes validation and ownership harder.

## Operating Model

| Activity | Cadence | Owner | Evidence |
|---|---|---|---|
| Source inventory check | Daily during pilot, weekly after stabilization | SOC | Log Analytics source inventory query |
| Agent health check | Daily during pilot | Platform or SOC | Wazuh active agent list |
| Detection review | Weekly | Detection engineer | Rule volume, false positives, tuning notes |
| Posture backlog review | Weekly | Security leader or risk owner | Backlog item status |
| Cost review | Weekly during pilot | Platform owner | OCI cost report |
| Teardown drill | Before demo reuse and after pilot | Demo owner | Clean destroy/resource search evidence |

## Production Exit Criteria

The pilot is ready to become a production design only when:

- source inventory is stable,
- agent health is monitored,
- data retention is approved,
- dashboard ownership is assigned,
- rule ownership is assigned,
- false-positive tuning process exists,
- access model is approved,
- cost model is understood,
- teardown and rollback are tested,
- escalation path is documented.

## Risk Register

| Risk | Impact | Mitigation |
|---|---|---|
| Over-broad IAM | Deployment grants more access than needed. | Scope policies to the lab compartment and document exceptions |
| Public dashboard exposure | Wazuh UI becomes reachable from the internet. | Keep dashboard tunnel-only and validate ingress rules |
| Stale GOAD agents | Reused hosts keep demo software after destroy. | Run `make down` and validate GOAD cleanup |
| Missing source families | Dashboards show incomplete evidence. | Use source inventory before demo interpretation |
| Ingestion lag | Fresh events appear missing. | Teach delivery windows and connector health checks |
| Cost drift | Logs and compute continue after demo. | Use tags, cost estimate, scheduled teardown, and resource search |

## Related Pages

- [Product roadmap and use cases](WAZUH_LOG_ANALYTICS_PRODUCT_ROADMAP.md)
- [Product capabilities](WAZUH_LOG_ANALYTICS_PRODUCT_CAPABILITIES.md)
- [Learner workbook](WAZUH_LOG_ANALYTICS_LEARNER_WORKBOOK.md)
- [Glossary and FAQ](WAZUH_LOG_ANALYTICS_GLOSSARY_FAQ.md)
- [End-to-end demo runbook](../END_TO_END_DEMO.md)
