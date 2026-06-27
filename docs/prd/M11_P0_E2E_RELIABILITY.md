# M11 P0: Deploy-Ready E2E Reliability and Safe Teardown

| Field | Value |
|---|---|
| Status | Approved for implementation |
| Version | 1.0 |
| Last updated | 2026-06-27 |
| Release target | `v0.5.0-rc.1` |
| Milestone | [M11 P0 – E2E Reliability](https://github.com/adibirzu/OCI-Wazuh/milestone/1) |

## Summary

M11 turns the current OCI Resource Manager release candidate into a repeatable,
idempotent live deployment. A protected run must safely deploy from clean and
partial state, validate Wazuh and real OCI telemetry, clean only lab-owned
resources and project-installed host components, and prove that teardown left
no project-owned OCI resources.

The release remains blocked until one protected live run completes the required
matrix and the release contains both `oci-wazuh-orm-stack.zip` and
`oci-wazuh-orm-stack.zip.sha256`.

## Problem statement

The release candidate has the expected Terraform, bootstrap, validation, and
teardown surfaces, but live attempts exposed failure modes that prevent a safe
one-click release:

- local profile selection can diverge from profile-free Resource Manager;
- OCI provider list data sources can return null for namespace, availability
  domain, or compatible image lookups even when OCI CLI discovery succeeds;
- a failed apply can leave deterministic resources that conflict with a retry;
- Service Connector quota can be exhausted by existing or deleted lifecycle
  records;
- provider import defects can make a safe existing resource unusable;
- stale validation artifacts can make a later run appear green;
- teardown evidence does not yet prove both shared-host cleanup boundaries and
  zero residual project resources.

A retry must not blindly recreate, adopt, replace, or delete resources. It must
classify the observed state, prove ownership and configuration equivalence, and
either reconcile safely or stop before mutation with actionable redacted
evidence.

## Personas

| Persona | Need |
|---|---|
| Lab operator | One controller for preflight, deploy, validate, debug, and teardown. |
| OCI/Terraform maintainer (Terra) | Deterministic compatibility, reconciliation, quota, and lifecycle behavior. |
| Validation/release maintainer (Luna) | Fresh evidence, complete capability gates, regression coverage, and a binary release decision. |
| Shared-environment owner | Assurance that unrelated OCI resources and pre-existing host software remain untouched. |
| Security reviewer | Redacted evidence, private workloads, bastion-only Wazuh access, and auditable ownership decisions. |

## Goals and non-goals

### Goals

- Deploy from clean state and recover from supported partial-apply state.
- Produce the same terminal state after repeated reconciliation and apply.
- Validate Wazuh, two Linux agents, FIM, real OCI Audit and Flow detections,
  Wazuh/OpenSearch views, Management Dashboard, and Log Analytics freshness.
- Make Windows behavior explicit for `skip`, `new_windows`, `reuse_goad`, and
  `install_goad`.
- Clean only Terraform-owned OCI resources and ownership-marked components on
  reused hosts.
- Prove zero project-tagged residual OCI resources after teardown.

### Non-goals

- Adopting resources based only on a display name or prefix.
- Repairing or deleting unrelated tenancy resources to make quota available.
- Modifying shared routes, shared GOAD infrastructure, or pre-existing endpoint
  software not installed by this project.
- Treating synthetic detections as proof of live OCI ingestion.
- Expanding P1–P3 roadmap capabilities into M11 implementation work.
- Publishing a production-supported Wazuh service or a direct public Wazuh
  endpoint.

## Success metrics

| Metric | Required result |
|---|---|
| Clean deployment | Full protected run reaches `validated` with no manual resource repair. |
| Partial recovery | Supported partial state reconciles to the same plan as a clean deployment. |
| Idempotence | A second reconcile/plan reports no unintended create, replace, or delete. |
| Telemetry freshness | Real rules `100000` and `100100` and analytics evidence are newer than the run start. |
| Endpoint coverage | Two Linux agents are active and current-run FIM evidence exists. |
| Network posture | Wazuh is bastion-only and every workload has no public address. |
| Teardown safety | No unowned deletion and no unmarked reused-host component removal. |
| Residual resources | Bounded post-teardown searches return zero project-owned OCI resources. |
| Test quality | Terraform 1.5.7 validation passes and measured Python coverage is at least 80%. |

## Security constraints

- All OCI resources use `project=oci-wazuh-demo`; ownership checks also require
  a resource-specific configuration fingerprint.
- Tenancy data, OCIDs, credentials, endpoints, IP topology, namespaces,
  fingerprints, personal paths, and raw live evidence must not enter committed
  files or release artifacts.
- Wazuh access is through a bastion tunnel only. A direct public path is a gate
  failure, not a fallback.
- Workloads remain private. Only the bastion may receive a public address.
- Reconciliation and teardown fail closed on missing, ambiguous, or conflicting
  ownership evidence.
- Secrets remain in environment variables or OCI Vault and are never inputs to
  Terraform state where an instance-principal retrieval path exists.
- Every generated evidence record carries the current run ID and passes the
  project redaction gate.

## Deployment state model

| State | Entry condition | Permitted next state | Required evidence |
|---|---|---|---|
| `clean` | No matching project resources are found and state has no managed objects. | `reconciled` | Discovery inventory and quota preflight. |
| `partial` | State or OCI contains a subset of expected resources after an interrupted or failed run. | `reconciled` or stop | Per-resource ownership and fingerprint classification. |
| `reconciled` | Every expected object is classified as managed/imported/create; no blocker remains. | `validated` or stop-after | Redacted reconciliation report and reviewed plan. |
| `validated` | Apply completed and all required current-run capability gates passed. | `teardown-ready` | Acceptance matrix and freshness evidence. |
| `teardown-ready` | Reused-host ownership cleanup passed and the saved teardown plan passed its guard. | `destroyed` | Cleanup markers and guarded plan report. |
| `destroyed` | Saved plan applied and bounded residual checks found zero project-owned resources. | Terminal | Redacted terminal summary and zero-residual report. |

Any state may stop as failed without being promoted. An operator stop-after
request records an incomplete terminal status and never satisfies a release
gate. Resumption creates a new run ID and re-evaluates observed state.

## Reconciliation policy

- **RP-01 — Discover:** inventory deterministic candidates before Terraform
  apply, including dynamic groups, IAM policies, logging groups, logs,
  configurations, Service Connectors, streams, bootstrap objects, and dashboard
  imports.
- **RP-02 — Prove ownership:** require the expected project tag or an equivalent
  immutable project ownership marker. Name matching alone is insufficient.
- **RP-03 — Prove equivalence:** compute a documented, resource-specific
  fingerprint from stable expected configuration. Exclude generated timestamps,
  lifecycle status, and other volatile fields.
- **RP-04 — Adopt narrowly:** import only one unambiguous, active,
  project-owned exact fingerprint match into the expected Terraform address.
- **RP-05 — Block safely:** classify name-only, ambiguous, drifted, unowned, or
  non-importable matches as blocked. Do not mutate them. Report the expected
  address, mismatch category, and a redacted operator remediation path.
- **RP-06 — Report:** distinguish `imported`, `create`, `blocked`, and
  `externally_owned`; bind the report to the run ID and plan input digest.

Provider import defects are not permission to recreate or replace a resource.
The run blocks until the provider/version issue is corrected or an explicit,
reviewed operator remediation restores a safely importable state.

## Capacity policy

- **CP-01:** query Service Connector limits, current usage, and matching active
  connectors before plan or apply.
- **CP-02:** import an exact active project-owned connector match instead of
  attempting a duplicate.
- **CP-03:** ignore deleted lifecycle entries as adoption candidates; retain
  their presence only as diagnostic evidence when OCI still counts them.
- **CP-04:** never stop, delete, replace, or adopt an externally owned connector.
- **CP-05:** if safe reuse is unavailable and capacity is insufficient, block
  before apply with quota name, required capacity, and redacted remediation.

## Provider compatibility policy

- **PC-01:** Resource Manager provider configuration remains region-only and
  profile-free. Local CLI binds `oci_config_profile` only when it is explicitly
  supplied; implicit profile selection is forbidden.
- **PC-02:** Object Storage namespace, Log Analytics namespace, availability
  domain, and compatible image values may use explicit overrides when an OCI
  provider list data source returns null.
- **PC-03:** an override is accepted only when same-run OCI CLI preflight proves
  it in the selected region and compartment. Evidence is summarized and
  redacted; raw identifiers are not committed.
- **PC-04:** local `cap`-style inputs and ORM-style inputs must both pass the
  Terraform plan matrix under Terraform 1.5.7.

## Teardown contract

- **TC-01:** clean reused hosts before deleting the control path needed to reach
  them.
- **TC-02:** remove a Wazuh agent, Sysmon, relay, staging directory, firewall
  rule, or Wazuh manager record only when the project ownership marker says this
  run/project installed it.
- **TC-03:** preserve and report pre-existing or unmarked components; never infer
  ownership from a product name alone.
- **TC-04:** generate a saved Terraform teardown plan, review its project
  ownership evidence, and apply that exact plan only after the guard passes.
- **TC-05:** search for project-owned OCI resources after apply with bounded
  retries for eventual consistency. Exhausting the retry budget is failure.
- **TC-06:** terminal evidence must show reused-host cleanup outcomes, guarded
  plan outcome, retry count, and zero residual project resources, with all
  sensitive values redacted.

## Acceptance criteria

- **AC-01:** ORM plan is profile-free; local plan uses an explicit supplied
  profile and never silently changes profile.
- **AC-02:** null provider list results either resolve through a CLI-verified
  override or fail before apply with actionable evidence.
- **AC-03:** clean deployment succeeds and a second reconciliation is
  idempotent.
- **AC-04:** supported partial state imports exact owned matches; name-only,
  ambiguous, drifted, or external matches are blocked without mutation.
- **AC-05:** Service Connector preflight safely reuses an exact active match or
  proves capacity; exhaustion blocks before apply.
- **AC-06:** one controller creates a unique run ID and runs preflight,
  reconciliation, apply, validation, and teardown without stale artifacts.
- **AC-07:** validation proves bastion-only Wazuh access, private workloads, two
  active Linux agents, and current-run FIM evidence.
- **AC-08:** real OCI Audit rule `100000` and Flow rule `100100` detections are
  newer than the current run start; synthetic events cannot satisfy this gate.
- **AC-09:** Wazuh/OpenSearch views, Management Dashboard, and Log Analytics all
  contain current-run evidence.
- **AC-10:** selected Windows behavior passes or uses only an allowed explicit
  skip; reused-host cleanup changes ownership-marked components only.
- **AC-11:** a guarded saved plan completes and bounded residual checks prove
  zero project-owned OCI resources.
- **AC-12:** unit and mocked integration tests pass, Terraform validates under
  1.5.7, package/schema/redaction checks pass, and Python coverage is at least
  80%.

## Acceptance matrix

All rows require AC-01 through AC-12. `Required` means the capability must be
green. `Allowed skip` must include a machine-readable reason and cannot mask a
failed attempted capability.

| Ingestion mode | Windows mode | Audit `100000` | Flow `100100` | Windows gate | Cleanup gate |
|---|---|---|---|---|---|
| `streaming` | `skip` | Required | Required through Connector Hub/Streaming | Allowed skip: mode selected before apply | No Windows host cleanup; zero residuals required |
| `streaming` | `new_windows` | Required | Required through Connector Hub/Streaming | Required | Terraform-owned host/components removed |
| `streaming` | `reuse_goad` | Required | Required through Connector Hub/Streaming | Required | Ownership-marked components removed; shared hosts preserved |
| `streaming` | `install_goad` | Required | Required through Connector Hub/Streaming | Required protected manual gate | Terraform-owned hosts/components removed |
| `object_storage` | `skip` | Required | Required through private batch object path | Allowed skip: mode selected before apply | No Windows host cleanup; zero residuals required |
| `object_storage` | `new_windows` | Required | Required through private batch object path | Required | Terraform-owned host/components removed |
| `object_storage` | `reuse_goad` | Required | Required through private batch object path | Required | Ownership-marked components removed; shared hosts preserved |
| `object_storage` | `install_goad` | Required | Required through private batch object path | Required protected manual gate | Terraform-owned hosts/components removed |
| `direct_api` | `skip` | Required | Required through private batch object path | Allowed skip: mode selected before apply | No Windows host cleanup; zero residuals required |
| `direct_api` | `new_windows` | Required | Required through private batch object path | Required | Terraform-owned host/components removed |
| `direct_api` | `reuse_goad` | Required | Required through private batch object path | Required | Ownership-marked components removed; shared hosts preserved |
| `direct_api` | `install_goad` | Required | Required through private batch object path | Required protected manual gate | Terraform-owned hosts/components removed |

Skipped capability rules:

1. Only a capability excluded by an explicit pre-apply mode may be skipped.
2. `windows_mode=skip` is the only ordinary Windows skip. `install_goad` may be
   marked pending only outside the protected manual gate; it cannot make a
   release run green.
3. Audit, Flow, Linux agents, FIM, network posture, dashboards, Log Analytics,
   guarded teardown, and zero residuals are never skippable.
4. Quota exhaustion, provider errors, failed cleanup, missing evidence, stale
   evidence, or a stop-after request are failures, not skips.

## Backlog and dependency order

| Issue | Owner | Depends on | Acceptance ownership |
|---|---|---|---|
| [#6 — Provider compatibility](https://github.com/adibirzu/OCI-Wazuh/issues/6) | Terra | — | PC-01–PC-04, AC-01, AC-02 |
| [#7 — Partial-apply reconciliation](https://github.com/adibirzu/OCI-Wazuh/issues/7) | Terra | #6 | RP-01–RP-06, AC-03, AC-04 |
| [#8 — Connector quota/lifecycle](https://github.com/adibirzu/OCI-Wazuh/issues/8) | Terra | #7 | CP-01–CP-05, AC-05 |
| [#9 — Guarded teardown](https://github.com/adibirzu/OCI-Wazuh/issues/9) | Terra | #7 | TC-01–TC-06, AC-10, AC-11 |
| [#10 — Live E2E orchestrator](https://github.com/adibirzu/OCI-Wazuh/issues/10) | Luna | #6–#9 | AC-06 |
| [#11 — Validation hardening](https://github.com/adibirzu/OCI-Wazuh/issues/11) | Luna | #10 | AC-07–AC-10 |
| [#12 — Regression matrix](https://github.com/adibirzu/OCI-Wazuh/issues/12) | Luna | #6–#11 | AC-03–AC-06, AC-10–AC-12 |
| [#13 — Operator/release docs](https://github.com/adibirzu/OCI-Wazuh/issues/13) | Luna | #10–#12 | AC-12, release gates |

## Release gates

- **RG-01:** issues #6–#13 are complete and their required tests are green.
- **RG-02:** one protected live run records clean deployment and supported
  partial-apply recovery, then completes the selected acceptance-matrix row.
- **RG-03:** the same run reaches `destroyed` with zero residual project
  resources and redacted evidence under `artifacts/validation/`.
- **RG-04:** only after RG-01–RG-03 may `v0.5.0-rc.1` attach the release ZIP and
  checksum or enable the public deploy path.
