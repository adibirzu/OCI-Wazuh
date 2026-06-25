# Wazuh and OCI Log Analytics Facilitator Guide

Use this guide to run a workshop or customer demo on Wazuh plus OCI Log Analytics. The target audience is security engineering, SOC, cloud operations, and platform teams.

## Workshop Goals

- Show Wazuh as the endpoint detection and rule engine.
- Show OCI Log Analytics as the cross-source correlation and dashboard layer.
- Prove real OCI Audit and VCN Flow ingestion.
- Connect detections to concrete hardening decisions.
- Leave participants with reusable commands, dashboards, and posture backlog templates.

## Timing

| Segment | Time | Goal |
|---|---:|---|
| Setup and mission | 10 min | Explain architecture and safety model |
| Wazuh endpoint detections | 20 min | Show Linux FIM/SCA and GOAD/Sysmon views |
| OCI log ingestion | 25 min | Validate Audit and VCN Flow records in Wazuh |
| OpenSearch views | 15 min | Explain `wazuh-alerts-*`, `oci-audit-*`, and `oci-flow-*` |
| Log Analytics dashboards | 30 min | Build source inventory and correlation panels |
| Investigation drill | 20 min | Pivot from Wazuh alert to Log Analytics context |
| Posture backlog | 20 min | Convert detections into security improvements |
| Teardown and questions | 10 min | Confirm cleanup expectations |

## Pre-Workshop Checklist

Run these commands before participants join:

```bash
make cap-preflight
make e2e
make goad-validate
make wazuh-content
make validate-real-oci-logs
make validate-opensearch-oci
make log-analytics-bridge
```

Confirm:

- Wazuh login opens through the local SSH tunnel.
- All expected Linux and GOAD agents are active.
- OCI Audit rule `100000` fired from real OCI telemetry.
- VCN Flow rule `100100` fired from real VCN Flow telemetry.
- Log Analytics source inventory includes Wazuh alerts, OCI Audit, VCN Flow, Linux, Windows, and Sysmon sources.
- Screenshots in `docs/wiki/assets/` contain no secrets or tenant-specific values.

## Demo Script

1. Open [Security Posture Wiki](WAZUH_LOG_ANALYTICS_SECURITY_POSTURE.md) and state the mental model: Wazuh detects, Log Analytics correlates.
2. Open the Wazuh tunnel and show the login page.
3. In Wazuh Discover, show the index/data view selector. Point out `wazuh-alerts-*`, `oci-audit-*`, and `oci-flow-*`.
4. Run or show output from `make e2e`, then filter for Linux FIM/SCA.
5. Run or show output from `make goad-validate`, then filter for GOAD Windows/Sysmon events.
6. Run or show output from `make validate-real-oci-logs`, then filter for rules `100000-100199`.
7. Open the OCI raw data views and explain why raw records are separate from alert records.
8. In OCI Log Analytics, run source inventory first:

```text
* | stats count by "Log Source" | sort -count
```

9. Build or show dashboard panels from `dashboards/log-analytics/oci-wazuh-dashboard-queries.json`.
10. Run the investigation drill from [Lesson 0003](../../lessons/0003-investigate-cloud-endpoint-network.html).
11. Finish by creating three posture backlog items from [Lesson 0004](../../lessons/0004-turn-detections-into-posture-backlog.html).

## Participant Exercises

| Exercise | Prompt | Expected output |
|---|---|---|
| Source inventory | Which log sources are present? | List of available Log Analytics sources |
| Wazuh detection | Which rules fired for OCI logs? | Rule `100000` and/or `100100` evidence |
| Raw source pivot | What raw OCI record explains the alert? | Audit or Flow fields copied into notes |
| Correlation | What other source supports the same event? | OS, Sysmon, Audit, Flow, or Wazuh alert context |
| Posture backlog | What should the company improve? | Evidence, owner, action, verification query |

## Common Failure Points

| Symptom | Likely cause | Teaching response |
|---|---|---|
| Log Analytics saved search returns zero rows | Source name differs or propagation is delayed | Run source inventory and confirm exact source names |
| Wazuh has alerts but Log Analytics does not | Unified Agent or Connector Hub delay | Generate a fresh alert and wait before debugging rules |
| GOAD hosts are missing | GOAD reuse not run, WinRM blocked, or cleanup already ran | Run `make goad-discover`, then `make goad-up` |
| OCI Flow alerts are missing | Flow Logs, Connector Hub, Streaming, or consumer path is delayed | Run `make validate-real-oci-logs` and inspect artifacts |
| Dashboard has raw logs but no posture outcome | Analyst stopped at visibility | Force the backlog-item exercise |

## Closeout

End every session with:

```bash
make down
```

For a long-running demo, explicitly state who owns the running cost, when it will be destroyed, and how reused GOAD agents will be removed.
