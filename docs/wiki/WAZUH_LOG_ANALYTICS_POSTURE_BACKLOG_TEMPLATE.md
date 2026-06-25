# Wazuh and OCI Log Analytics Posture Backlog Template

Use this template to convert Wazuh and Log Analytics findings into work that improves company security posture.

## Backlog Item

```text
Title:
Control category: identity | endpoint | network | vulnerability | logging | response
ATT&CK technique:
Evidence:
Wazuh view or rule:
Log Analytics query:
Affected entities:
Risk statement:
Owner:
Action:
Due date:
Verification query:
Closure evidence:
```

## Example: Denied Traffic Spike

```text
Title: Review denied traffic spike against workload subnet
Control category: network
ATT&CK technique: T1046
Evidence: Wazuh rule 100100 and VCN rejects by source/destination
Wazuh view or rule: rule.id >= 100100 and rule.id <= 100199
Log Analytics query: VCN rejects by pair
Affected entities: monitored workload subnet and destination host
Risk statement: repeated denied traffic may indicate discovery activity or an unapproved scanner
Owner: network security
Action: confirm source, approve scanner or tighten NSG policy
Due date: next review cycle
Verification query: reject count by pair no longer shows unexpected source/destination
Closure evidence: query screenshot or exported result plus NSG change record
```

## Example: Privileged OCI Activity

```text
Title: Validate privileged OCI API activity from unusual source
Control category: identity
ATT&CK technique: T1078
Evidence: OCI Audit event and Wazuh rule 100000
Wazuh view or rule: rule.id >= 100000 and rule.id <= 100099
Log Analytics query: OCI Audit by user and source
Affected entities: target compartment or resource family
Risk statement: privileged activity from an unusual source may indicate credential misuse
Owner: IAM owner
Action: validate user, enforce MFA, reduce broad policy if not justified
Due date: next identity review
Verification query: same activity appears only from approved source and identity path
Closure evidence: IAM review note plus query result
```

## Review Cadence

| Cadence | Activity |
|---|---|
| Daily | Review high-severity alerts and failed ingestion gates. |
| Weekly | Review posture backlog, top rejected flows, top Audit event sources, and top SCA failures. |
| Monthly | Review detection ownership, ATT&CK coverage, data retention, cost, and access controls. |
| Quarterly | Re-run the assessment and update rollout scope. |

## Done Criteria

A posture item is done only when:

- the owner accepted the risk or implemented the action,
- the verification query shows the expected change,
- dashboards or Wazuh views are updated if the detection was tuned,
- the closure evidence is linked from the backlog item.
