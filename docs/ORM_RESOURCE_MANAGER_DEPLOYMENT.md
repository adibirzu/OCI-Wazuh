# OCI Resource Manager deployment

The M11 stack is implemented as a release candidate. The Terraform root is the
source of truth; packaging, host bootstrap, validation, and safe teardown use
small deterministic Python or shell helpers.

The deploy button must not be described as production-ready until the
environment-protected `live-m11` workflow passes and a release attaches both
`oci-wazuh-orm-stack.zip` and `oci-wazuh-orm-stack.zip.sha256`.

The public deploy link is intentionally disabled while this release candidate lacks a protected live M11 result and attached release artifacts.

## Build and inspect the artifact

```bash
make test
make lint
make schema-validate
make orm-package
unzip -l artifacts/orm/oci-wazuh-orm-stack.zip
```

The packager uses explicit allowlists, normalized ZIP metadata, a SHA-256
sidecar, and a JSON manifest. It excludes tfvars, state, caches, browser
profiles, validation evidence, local configuration, and SSH keys. Tests build
the artifact twice and require identical bytes, validate its file list, and
scan all public text for OCI identifiers and sensitive topology.

The ZIP root contains `schema.yaml`, Terraform root files, relative modules,
the private bootstrap bundle and manifest, rules/decoders/consumer assets,
dashboard definitions, and this public-safe README.

## Resource Manager inputs

Resource Manager automatically supplies `tenancy_ocid`, `compartment_ocid`,
and `region`. The stack provider block requires only `region`, following
[Oracle's Resource Manager guidance](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Concepts/terraformconfigresourcemanager.htm).
The console form is defined by the ZIP-root
[`schema.yaml`](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Concepts/terraformconfigresourcemanager_topic-schema.htm).

Required operator input:

- a restricted `operator_cidr`; unrestricted IPv4 and IPv6 CIDRs are rejected;
- `ssh_public_key` content; ORM never reads a local key path;
- mode selections appropriate for the target compartment.

`tenancy_id` and `compartment_id` remain deprecated local-CLI aliases for one
release. `windows_mode=auto` normalizes to `skip`, and
`ingestion_mode=log_analytics_bridge` normalizes to `direct_api` with Log
Analytics enabled.

## Mode behavior

Networking:

- `create` owns an isolated VCN, public bastion subnet, private workload
  subnet, Internet/NAT/service gateways, route tables, default-deny ingress
  security lists, and role-specific NSGs.
- `existing` creates only project NSGs and compute attachments. It does not
  modify shared route tables. The supplied subnets must already provide the
  required reachability.

Only the bastion receives a public IP. Wazuh, Linux agents, Windows hosts,
GOAD hosts, and the orchestration runner are private.

Ingestion:

- `streaming`: Flow Logs use Connector Hub and Streaming; Audit uses the real
  OCI Audit API.
- `object_storage`: Flow Logs use a private batch bucket; Audit uses the Audit
  API.
- `direct_api`: Audit uses the Audit API and Flow Logs use the private batch
  bucket so the real Flow detection gate remains available.

Windows:

- `skip`: no Windows resources and an explicit skipped gate.
- `new_windows`: one private Windows Server 2022 instance.
- `reuse_goad`: explicit existing instance OCIDs; shared routes are untouched.
- `install_goad`: five private Windows hosts with GOADv3-compatible names and
  a pinned upstream attribution boundary.

For `install_goad`, `goad_vault_secret_id` must reference a JSON secret with
`domain_admin_passwords` keys for `sevenkingdoms.local`,
`north.sevenkingdoms.local`, and `essos.local`. Each value must be at least 14
characters. The private runner retrieves and validates the secret with its
instance principal at runtime; secret values are never passed to Terraform.

All non-skip Windows paths use OCI Agent Run Command from a private,
Terraform-managed runner. Wazuh and Sysmon are installed only when absent, and
the local marker records which components are project-owned. Cleanup removes
only those components. The five-host GOAD infrastructure path remains a manual
release gate: it cannot be declared green until the selected Vault-backed AD
provisioning run passes in the protected live environment.

## Bootstrap and IAM

Terraform uploads a private JSON bootstrap archive and SHA-256 manifest to a
project bucket. Instance principals retry through IAM propagation, verify the
bundle and every asset before extraction, install pinned Wazuh 4.14.x inputs,
and publish explicit status markers. No SSH private key or WinRM password is
stored by ORM.

Policies are separated by purpose: bundle/status objects, Audit/transport
consumption, Connector Hub source/target access, Unified Agent Wazuh and
Windows/Sysmon publication, and Windows Run Command execution.

## Live M11 gate

The protected workflow invokes one controller:

```bash
python3 scripts/m11-live.py --mode orm --project-name oci-wazuh-demo
```

The controller creates a unique run ID before preflight and runs discovery,
reconciliation, apply, validation, ownership cleanup, guarded teardown, and
bounded residual checks. The workflow input `stop_after` may retain a stage for
debugging, but any stopped run is incomplete and cannot satisfy a release gate.

Preflight derives expected resources from the Terraform JSON plan and compares
them with OCI Search and Service Connector inventory. Automatic import requires
the project tag and exact configuration fingerprint. Name-only, external,
ambiguous, drifted, deleted, or provider-non-importable matches block without
mutation. The redacted report distinguishes `create`, `import`, `blocked`, and
external ownership; runtime identifiers remain outside uploaded evidence.

Service Connector limits and active usage are queried before apply. An exact
active project match may be imported. Deleted records are ignored for adoption,
and unrelated connectors are never stopped or removed. If capacity remains
exhausted, request quota, wait for lifecycle accounting, or reduce the selected
connector footprint before rerunning.

The protected run requires:

1. bastion-only Wazuh access and API authentication;
2. two active Linux agents and FIM evidence;
3. the selected Windows mode or an explicit skip;
4. real Audit rule `100000` and Flow rule `100100` detections;
5. Wazuh/OpenSearch data views;
6. the idempotently imported Management Dashboard;
7. recent Wazuh alerts in OCI Logging and Log Analytics;
8. guarded destroy and zero residual project-tagged resources.

Evidence uses only `green|failed|skipped`, carries the current run ID, and is
newer than the run start. Stale gate files are deleted at initialization and
cross-run gate documents are rejected. Public Wazuh SSH is not a
release-validation fallback.

For `reuse_goad`, teardown is two phase:

```bash
# 1. update reuse_goad_action to cleanup and apply
terraform -chdir=terraform apply

# 2. verify the cleanup Run Command output markers
make validate-windows

# 3. run guarded destroy and residual-resource verification
DESTROY_CONFIRM=oci-wazuh-demo make down
```

Full GOAD and managed OpenSearch runs are manual protected release gates due
to cost. `v0.5.0-rc.1` remains blocked until the selected capability matrix is
green, teardown proves zero project-owned resources, and the release attaches
both `oci-wazuh-orm-stack.zip` and `oci-wazuh-orm-stack.zip.sha256`.
