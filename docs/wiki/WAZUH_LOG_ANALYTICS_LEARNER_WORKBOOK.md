# Wazuh and OCI Log Analytics Learner Workbook

Use this workbook during a workshop, self-paced lab, or internal enablement session. It gives learners concrete prompts, evidence slots, and completion criteria.

Do not paste real OCIDs, IP addresses, credentials, Terraform state, raw screenshots, or tenant-specific logs into a shared workbook. Use placeholders.

## Learner Profile

| Field | Notes |
|---|---|
| Name | |
| Role | SOC analyst / cloud security / platform / detection engineer / leader |
| Session date | |
| Lab version | |
| Instructor or owner | |

## Preflight Checklist

| Check | Complete | Evidence |
|---|---|---|
| I can open the hosted docs. | [ ] | |
| I know whether this is standalone or OCI-DEMO attached. | [ ] | |
| I know whether Windows uses GOAD or a new Windows host. | [ ] | |
| I know where Wazuh is accessed from the SSH tunnel. | [ ] | |
| I know which sources should appear in Log Analytics. | [ ] | |
| I know the teardown command. | [ ] | |

## Exercise 1: Source Inventory

Goal: prove which telemetry sources are present before interpreting dashboards.

Run or review the source inventory query in Log Analytics:

```text
* | stats count by "Log Source" | sort -count
```

Record the result:

| Source family | Present | Notes |
|---|---|---|
| Wazuh alert custom log | [ ] | |
| OCI Audit Logs | [ ] | |
| OCI VCN Flow Unified Schema Logs | [ ] | |
| Linux Syslog Logs | [ ] | |
| Linux Secure Logs | [ ] | |
| Windows Security Events | [ ] | |
| Windows Sysmon Events | [ ] | |

Completion evidence:

```text
Source inventory completed at <TIME>. Missing sources: <LIST_OR_NONE>.
```

## Exercise 2: Wazuh Navigation

Goal: distinguish detection alerts from raw source records.

Open Wazuh Discover and identify:

| View | Purpose | Found |
|---|---|---|
| `wazuh-alerts-*` | Wazuh detections and rule context | [ ] |
| `oci-audit-*` | Normalized raw OCI Audit records | [ ] |
| `oci-flow-*` | Normalized raw VCN Flow records | [ ] |

Answer:

```text
I use wazuh-alerts-* when...
I use oci-audit-* when...
I use oci-flow-* when...
```

## Exercise 3: OCI Audit Investigation

Goal: follow one cloud control-plane event from raw record to detection and correlation.

Evidence fields:

| Field | Value |
|---|---|
| Time window | |
| Event type | |
| Principal | |
| Source IP placeholder | |
| Compartment placeholder | |
| Wazuh rule ID | |
| Log Analytics query used | |

Decision:

```text
Decision: accept / tune / investigate / harden
Reason:
Next action:
Owner:
Verification query:
```

## Exercise 4: VCN Flow Investigation

Goal: explain denied or unusual traffic with parsed network fields.

Evidence fields:

| Field | Value |
|---|---|
| Time window | |
| Source placeholder | |
| Destination placeholder | |
| Destination port | |
| Protocol | |
| Action | ACCEPT / REJECT |
| Bytes | |
| Packets | |
| Wazuh rule ID | |

Decision:

```text
Decision: accept / tune / investigate / harden
Reason:
Network owner:
Verification query:
```

## Exercise 5: Endpoint Posture

Goal: connect a host signal to a posture action.

Choose one:

- Linux FIM alert
- Linux SCA finding
- Wazuh vulnerability finding
- Windows or Sysmon event

Evidence:

| Field | Value |
|---|---|
| Host placeholder | |
| Agent status | |
| Signal type | |
| Rule or check ID | |
| Severity | |
| Supporting OS log | |

Posture item:

```text
Risk:
Action:
Owner:
Due date:
Verification:
```

## Exercise 6: Dashboard Row

Goal: build or explain one dashboard row that answers one security question.

| Dashboard row | Security question | Source views | Decision supported |
|---|---|---|---|
| | | | |

Good dashboard rows have:

- one clear question,
- one time window,
- source inventory awareness,
- a visible owner or action,
- no dependency on private identifiers in the title.

## Exercise 7: Detection Engineering

Goal: describe how a rule should be added or tuned.

| Item | Notes |
|---|---|
| Detection hypothesis | |
| Source fields required | |
| Expected true positive | |
| Expected false positive | |
| Rule range | `100000-100099` or `100100-100199` |
| Test command | |
| Documentation update | |

Completion evidence:

```text
The detection is ready when it has a rule, a test event, a false-positive note, a dashboard path, and an owner.
```

## Exercise 8: Teardown and Reuse Safety

Goal: prove the demo can be removed without contaminating reused hosts or shared resources.

Checklist:

| Cleanup item | Expected |
|---|---|
| Reused GOAD Wazuh agents removed | [ ] |
| Sysmon service removed when demo installed it | [ ] |
| Wazuh manager stale agent records removed | [ ] |
| Demo-owned OCI resources destroyed | [ ] |
| Shared OCI-DEMO or GOAD resources preserved | [ ] |
| Resource search by project tag is empty | [ ] |

Command:

```bash
make down
```

## Final Assessment

| Skill | Self score 1-5 | Evidence |
|---|---|---|
| Source inventory | | |
| Wazuh navigation | | |
| OCI Audit investigation | | |
| VCN Flow investigation | | |
| Endpoint posture | | |
| Dashboard explanation | | |
| Detection engineering | | |
| Teardown safety | | |

Completion statement:

```text
I can use Wazuh and OCI Log Analytics together to investigate endpoint, cloud, and network signals, then convert evidence into a posture action.
```

## Related Pages

- [Learning curve and role paths](WAZUH_LOG_ANALYTICS_LEARNING_CURVE.md)
- [Product roadmap and use cases](WAZUH_LOG_ANALYTICS_PRODUCT_ROADMAP.md)
- [Product capabilities](WAZUH_LOG_ANALYTICS_PRODUCT_CAPABILITIES.md)
- [Assessment](WAZUH_LOG_ANALYTICS_ASSESSMENT.md)
- [Participant handout](WAZUH_LOG_ANALYTICS_PARTICIPANT_HANDOUT.md)
