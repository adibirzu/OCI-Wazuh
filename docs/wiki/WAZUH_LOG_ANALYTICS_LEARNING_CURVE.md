# Wazuh and OCI Log Analytics Learning Curve

This page turns the lab into a structured learning journey. It helps a learner move from basic navigation to confident investigation, dashboard ownership, detection engineering, and production planning.

## Learning Principles

- Start from evidence, not dashboards. Confirm sources before interpreting widgets.
- Teach one signal at a time. A useful first signal is denied VCN Flow traffic or a known OCI Audit action.
- Keep raw source records separate from detections. Use `oci-audit-*` and `oci-flow-*` for normalized source data, and `wazuh-alerts-*` for Wazuh detections.
- End each exercise with a decision: accept, tune, investigate, or harden.
- Validate with commands, then explain with screenshots and dashboards.

## Skill Ladder

| Level | Learner can | Hands-on proof | Typical blocker |
|---|---|---|---|
| 1. Observer | Open Wazuh and Log Analytics, identify data views and sources. | Source inventory and Wazuh Discover screenshot | Confusing data views with alert indices |
| 2. Operator | Run validation targets and read pass/fail output. | `make e2e`, `make teach-validate` | Missing prerequisites or credentials |
| 3. Analyst | Investigate one signal across Wazuh, raw OCI data, and Log Analytics. | Three-line investigation note | Starting with too many sources |
| 4. Dashboard builder | Build a dashboard row that answers one security question. | Saved query or dashboard panel | Widget names not tied to questions |
| 5. Detection engineer | Add or tune rules and prove they fire safely. | Rule test plus alert evidence | Unclear field mapping or noisy conditions |
| 6. Platform owner | Operate deployment, ingestion, teardown, and cost guardrails. | Clean deploy/destroy run | Shared resources versus demo-owned resources |
| 7. Program owner | Convert findings into posture metrics and roadmap. | Backlog and executive metrics | No owner or verification query |

## Suggested Timelines

### Two-Hour Executive Demo

| Time | Activity | Outcome |
|---|---|---|
| 10 min | Explain architecture and safety boundaries. | Everyone understands tunnel-only Wazuh access and public-safe docs |
| 20 min | Show active agents and source inventory. | Endpoint, cloud, network, and Log Analytics sources are visible |
| 25 min | Walk one denied-flow investigation. | Wazuh alert, raw flow record, and Log Analytics row are connected |
| 25 min | Walk one OCI Audit investigation. | Principal, source IP, event type, and compartment are visible |
| 20 min | Convert evidence into posture action. | One hardening item with owner and verification query |
| 20 min | Review maturity model and next steps. | Audience sees how demo becomes program |

### Half-Day Analyst Workshop

| Block | Activity | Artifact |
|---|---|---|
| 1 | Source inventory and Wazuh navigation | Data-source checklist |
| 2 | Linux FIM/SCA and vulnerability posture | Endpoint posture note |
| 3 | OCI Audit and VCN Flow investigations | Investigation worksheet |
| 4 | GOAD/Sysmon or Windows path | Windows event pivot |
| 5 | Dashboard construction | Two saved dashboard rows |
| 6 | Posture backlog | Three prioritized remediation items |

### Two-Day Engineering Enablement

| Day | Focus | Exit criteria |
|---|---|---|
| 1 | Deploy, validate, ingest, and inspect. | Real OCI Audit and VCN Flow records visible in Wazuh and Log Analytics |
| 2 | Extend detections, dashboards, teardown, and production plan. | New rule or dashboard added, tested, documented, and assigned an owner |

## Role-Based Paths

### SOC Analyst Path

1. Read [Security posture wiki](WAZUH_LOG_ANALYTICS_SECURITY_POSTURE.md).
2. Complete lessons 0001, 0002, and 0003.
3. Use the query cookbook to run source inventory.
4. Write one investigation note with:
   - signal,
   - evidence,
   - related sources,
   - decision,
   - next action.

Completion proof:

```text
I can explain why the Wazuh alert fired, find the raw OCI record, and show one supporting Log Analytics query.
```

### Cloud Security Engineer Path

1. Read [Architecture and workflows](WAZUH_LOG_ANALYTICS_ARCHITECTURE.md).
2. Run the end-to-end deployment steps from [End-to-end demo runbook](../END_TO_END_DEMO.md).
3. Validate real OCI logs with `make validate-real-oci-logs`.
4. Confirm `oci-audit-*` and `oci-flow-*` OpenSearch views.
5. Document one tenancy-specific prerequisite without committing private values.

Completion proof:

```text
I can show the delivery path from OCI service log to Wazuh detection and Log Analytics correlation.
```

### Detection Engineer Path

1. Read [Query cookbook](WAZUH_LOG_ANALYTICS_QUERY_COOKBOOK.md).
2. Review rule ranges `100000-100099` and `100100-100199`.
3. Add or tune one rule in a branch.
4. Run synthetic validation and one real-log validation.
5. Update the detection catalog and MITRE mapping.

Completion proof:

```text
I can prove a rule fires for a known event, avoids a known false positive, and has an owner.
```

### Platform Owner Path

1. Read [Product capabilities](WAZUH_LOG_ANALYTICS_PRODUCT_CAPABILITIES.md).
2. Run prerequisite and cost checks.
3. Review teardown ownership for demo-created resources and reused GOAD hosts.
4. Confirm `make down` removes Wazuh agents from reused Windows hosts.
5. Capture a deployment decision record.

Completion proof:

```text
I can deploy and remove the lab without leaving demo-owned resources or agents behind.
```

### Security Leader Path

1. Review the capability map and maturity model.
2. Watch an analyst walk through one signal.
3. Ask for the posture backlog item and verification query.
4. Review executive metrics from lesson 0008.
5. Decide whether to move from demo to pilot.

Completion proof:

```text
I can connect the demo to measurable posture outcomes and accountable remediation.
```

## Learning Curve by Concept

| Concept | Beginner framing | Advanced framing | Practice |
|---|---|---|---|
| Wazuh agents | Hosts send logs and security events to Wazuh. | Agent groups, module config, enrollment, duplicate cleanup, and rule context. | Enroll Linux and GOAD hosts, then verify active status |
| FIM | A file changed. | Baseline, watched paths, alert severity, and change ownership. | Touch a watched file and find the alert |
| SCA | A hardening check passed or failed. | Policy coverage, exception workflow, and drift management. | Review failed checks and write one remediation item |
| OCI Audit | A cloud API action happened. | Principal, source, target, compartment, request metadata, and risk mapping. | Create and delete a harmless resource, then find the event |
| VCN Flow | Network traffic was accepted or rejected. | Flow direction, deny spikes, unusual egress, and service ownership. | Generate denied traffic and confirm parsed fields |
| Sysmon | Windows process and network behavior is visible. | Event ID selection, rule tuning, and AD attack-path context. | Confirm one benign Sysmon event from GOAD |
| Log Analytics | Search across multiple source families. | Entity mapping, source governance, dashboard ownership, and retention. | Build a source inventory panel |
| OpenSearch | Search raw and alert indices. | Index templates, data views, saved objects, and lifecycle planning. | Open `oci-audit-*` and `oci-flow-*` views |

## Common Learning Pitfalls

| Pitfall | Symptom | Corrective move |
|---|---|---|
| Skipping source inventory | Dashboard widgets are empty. | Run source inventory before editing queries |
| Mixing raw and alert indices | Fields appear missing or inconsistent. | Use raw OCI indices for source data and `wazuh-alerts-*` for detections |
| Treating synthetic detections as full proof | Rules fire but real logs are absent. | Run `make validate-real-oci-logs` |
| Ignoring ingestion lag | A fresh event is not visible immediately. | Wait for delivery windows and check connector health |
| Overbuilding dashboards | Many widgets, unclear decisions. | Tie every widget to one investigation question |
| Not planning teardown | Reused GOAD hosts keep stale agents. | Run `make down` and verify cleanup |

## Assessment Rubric

| Score | Description |
|---|---|
| 1 | Can describe Wazuh and Log Analytics but needs help navigating. |
| 2 | Can run validation commands and identify primary data views. |
| 3 | Can complete one guided investigation and explain the evidence. |
| 4 | Can build or tune a dashboard row and write a posture backlog item. |
| 5 | Can add or tune a detection, validate it, document it, and teach the workflow. |

## Related Pages

- [Product capabilities](WAZUH_LOG_ANALYTICS_PRODUCT_CAPABILITIES.md)
- [Module index](WAZUH_LOG_ANALYTICS_MODULE_INDEX.md)
- [Hands-on walkthrough](WAZUH_LOG_ANALYTICS_HANDS_ON.md)
- [Facilitator guide](WAZUH_LOG_ANALYTICS_FACILITATOR_GUIDE.md)
- [Assessment](WAZUH_LOG_ANALYTICS_ASSESSMENT.md)
