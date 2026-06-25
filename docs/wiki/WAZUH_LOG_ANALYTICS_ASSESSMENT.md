# Wazuh and OCI Log Analytics Assessment

Use this assessment after the workshop to verify that participants can operate the demo and apply it to a real company security posture program.

## Practical Tasks

| Task | Evidence required | Pass condition |
|---|---|---|
| Confirm Wazuh access | Tunnel command and Wazuh login screen | Dashboard reachable only through the tunnel |
| Confirm endpoint detections | Wazuh view for Linux FIM/SCA | At least one recent Linux FIM or SCA alert explained |
| Confirm GOAD/Sysmon path | Wazuh view for GOAD Windows/Sysmon | At least one Windows/Sysmon event tied to a host |
| Confirm real OCI Audit | Wazuh rule `100000` or raw `oci-audit-*` record | Real OCI event fields identified |
| Confirm real VCN Flow | Wazuh rule `100100` or raw `oci-flow-*` record | Source, destination, port, action, bytes, and packets identified |
| Confirm Log Analytics source inventory | Source inventory query output | Expected source families found or discrepancy documented |
| Build correlation row | Dashboard row with Wazuh, Audit, Flow, and OS/Windows context | One security question answered by cross-source data |
| Create posture backlog | Three backlog items | Each item has evidence, owner, action, and verification query |
| Promote a detection | Detection lifecycle card | Required fields, owner, tuning rule, and retirement condition documented |
| Report posture | Executive summary | Three metrics, two risks reduced, one gap, and one decision request |
| Teardown planning | Cleanup command and ownership note | Reused GOAD agents and demo resources have a clear removal path |

## Rubric

| Level | Description |
|---|---|
| 1. Awareness | Can describe Wazuh and Log Analytics roles but cannot validate data flow. |
| 2. Operator | Can run gates, open dashboards, and distinguish alerts from raw source records. |
| 3. Analyst | Can pivot from Wazuh alert to raw OCI record and Log Analytics context. |
| 4. Engineer | Can troubleshoot ingestion, tune views, and add detection-family dashboards. |
| 5. Program owner | Can turn detections into a prioritized posture backlog with owners and verification queries. |

## Scenario Questions

1. A VCN Flow widget returns zero rows. What is the first query you run and why?
2. Wazuh shows rule `100100`, but Log Analytics has no matching Wazuh alert source. Which delivery path do you check?
3. A privileged OCI API call appears in Audit logs from an unusual source IP. Which Wazuh and Log Analytics views do you open?
4. A Sysmon network event appears on a GOAD host. Which VCN Flow fields help confirm whether the traffic crossed expected boundaries?
5. A high-severity Wazuh alert repeats every day but no one acts on it. How do you convert it into a posture backlog item?

## Expected Answer Patterns

- Start with source inventory before changing Log Analytics dashboards.
- Use Wazuh alerts for detection context and raw OCI indices for source details.
- Validate real ingestion with `make validate-real-oci-logs`, not only synthetic events.
- Treat empty dashboards as an ingestion/source/query/time-range problem until proven otherwise.
- Close posture work with a repeatable verification query.

## Completion Record

Use this template for each participant or team:

```text
Team:
Date:
Wazuh validation gates completed:
Log Analytics source inventory completed:
Dashboard row created:
Posture backlog items created:
Remaining blockers:
Next review date:
```
