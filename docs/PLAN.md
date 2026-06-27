# Plan

## PRD and task coverage

M11 uses [M11 P0: Deploy-Ready E2E Reliability and Safe Teardown](prd/M11_P0_E2E_RELIABILITY.md)
as its source of truth. Work follows RPEQ per milestone: Research, Plan, Execute,
and QA.

| Milestone | Status | Existing implementation and validation ownership | Tracked work / release gate |
|---|---|---|---|
| M1 — Bootstrap/discovery | Complete | `make bootstrap`, repository/tool discovery | Bootstrap must remain green. |
| M2 — Network and compute | Implemented asset | `terraform/modules/network`, `terraform/modules/compute`, private workload checks | M11 AC-07 and #11 own live network validation. |
| M3 — Wazuh AIO | Implemented asset | `terraform/modules/wazuh-server`, bootstrap status, Wazuh API/dashboard checks | M11 #10 and #11 own current-run evidence. |
| M4 — Linux endpoints | Implemented asset | Linux cloud-init, enrollment, FIM validation | M11 AC-07 and #11 require two active agents and fresh FIM. |
| M5 — Windows/GOAD | Implemented asset | `windows_mode`, Run Command, GOAD assets, ownership markers | M11 AC-10, #9, and #11 own mode and cleanup gates. |
| M6 — OCI Audit | Implemented asset | Audit consumer and rule `100000` | M11 AC-08 and #11 own real-event freshness. |
| M7 — VCN Flow | Implemented asset | Flow Logs, Service Connector/transport, rule `100100` | M11 #8 and #11 own capacity, lifecycle, and freshness. |
| M8 — Wazuh/OpenSearch views | Implemented asset | Raw OCI indices, data views, saved searches/dashboard | M11 AC-09 and #11 own current-run view evidence. |
| M9 — Log Analytics | Implemented asset | Wazuh alert bridge, source/entity validation, dashboard queries | M11 AC-09 and #11 own freshness. |
| M10 — Teardown/package gates | Implemented asset | guarded plan, ORM packager, schema and redaction checks | M11 #9 and #12 own positive/negative teardown and regression proof. |
| M11 P0 — Deploy-ready E2E | Active | Provider compatibility, reconciliation, unified run control, full live matrix | #6–#13; release is blocked by RG-01–RG-04. |

## M11 P0 issue coverage

| Issue | Owner | Difficulty | Depends on | PRD criteria |
|---|---|---:|---|---|
| [#6 Local/ORM OCI provider compatibility](https://github.com/adibirzu/OCI-Wazuh/issues/6) | Terra | High | — | PC-01–PC-04, AC-01, AC-02 |
| [#7 Safe partial-apply reconciliation](https://github.com/adibirzu/OCI-Wazuh/issues/7) | Terra | High | #6 | RP-01–RP-06, AC-03, AC-04 |
| [#8 Service Connector quota/lifecycle guard](https://github.com/adibirzu/OCI-Wazuh/issues/8) | Terra | High | #7 | CP-01–CP-05, AC-05 |
| [#9 Guarded destroy and reused-host cleanup](https://github.com/adibirzu/OCI-Wazuh/issues/9) | Terra | High | #7 | TC-01–TC-06, AC-10, AC-11 |
| [#10 Unified live E2E orchestrator](https://github.com/adibirzu/OCI-Wazuh/issues/10) | Luna | Medium | #6–#9 | AC-06, AC-07, AC-12 |
| [#11 Wazuh and telemetry validation hardening](https://github.com/adibirzu/OCI-Wazuh/issues/11) | Luna | Medium | #10 | AC-07–AC-10, acceptance matrix |
| [#12 Regression and integration test matrix](https://github.com/adibirzu/OCI-Wazuh/issues/12) | Luna | Medium | #6–#11 | AC-03–AC-06, AC-10–AC-12 |
| [#13 Operator and release documentation](https://github.com/adibirzu/OCI-Wazuh/issues/13) | Luna | Medium | #10–#12 | AC-12, RG-01–RG-04 |

## Current release gate

`v0.5.0-rc.1` remains blocked. Packaging alone is not a release signal. Issues
#6–#13 must be complete, the protected live run must pass one selected matrix
row plus clean and partial-state scenarios, teardown must prove zero residual
project resources, and the release must attach both the ZIP and checksum.
