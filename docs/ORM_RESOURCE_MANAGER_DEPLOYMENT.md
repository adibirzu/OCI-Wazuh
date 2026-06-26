# OCI Resource Manager Deployment Plan

This page defines the planned OCI Resource Manager one-click deployment path for the OCI Wazuh Detection Lab.

## Planned Deploy Button

The deploy button target is the release artifact `oci-wazuh-orm-stack.zip`. The button becomes production-ready when the `v0.5.x` Resource Manager release attaches that ZIP and the M11 gate below is green.

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/adibirzu/OCI-Wazuh/releases/latest/download/oci-wazuh-orm-stack.zip)

Until the release artifact exists, use this local packaging command for validation:

```bash
make orm-package
```

The generated artifact is:

```text
artifacts/orm/oci-wazuh-orm-stack.zip
```

## End-to-End Feature Profile

The ORM stack must deploy the full demo path, not only the base compute layer.

Required features:

- Wazuh 4.14.x all-in-one manager, indexer, and dashboard.
- Bastion-only Wazuh dashboard access.
- Oracle Linux 9 and Ubuntu 24.04 Wazuh agents.
- FIM, SCA, syscollector, vulnerability detection, and Linux log collection.
- Windows path selection: skip, new Windows Server 2022, reuse GOAD, or install GOADv3 when supported.
- Sysmon and SOC Fortress rules for Windows or GOAD hosts.
- OCI Audit ingestion into Wazuh with rule IDs `100000-100099`.
- VCN Flow Log ingestion into Wazuh with rule IDs `100100-100199`.
- Dedicated OpenSearch data views for `wazuh-alerts-*`, `oci-audit-*`, and `oci-flow-*`.
- Optional OCI Search with OpenSearch backend.
- Wazuh alerts and host telemetry forwarded to OCI Log Analytics.
- Log Analytics dashboard query pack and freshness validation.
- Guarded teardown that removes only demo-owned resources and demo-installed reused-host agents.

## ORM Input Model

Resource Manager cannot depend on local files such as `~/.oci/config` or `~/.ssh/id_rsa.pub`. The Terraform root therefore supports:

- `oci_config_profile = ""` for ORM deployments.
- `ssh_public_key` for pasted public key content.
- `ssh_public_key_path` only for local CLI deployments.

Required user inputs:

| Variable | Purpose |
|---|---|
| `region` | OCI region for the lab. |
| `tenancy_id` | Tenancy OCID for availability-domain and image lookups. |
| `compartment_id` | Target compartment for demo resources. |
| `availability_domain` | Availability domain for compute instances. |
| `ol9_image_id` | Oracle Linux 9 image OCID. |
| `ubuntu2404_image_id` | Ubuntu 24.04 image OCID. |
| `bastion_subnet_id` | Public or existing bastion subnet. |
| `agent_subnet_id` | Workload subnet for Wazuh and agents. |
| `operator_cidr` | CIDR allowed to SSH to the bastion. |
| `ssh_public_key` | SSH public key content. |
| `ingestion_mode` | `streaming`, `object_storage`, `direct_api`, or `log_analytics_bridge`. |
| `windows_mode` | `auto`, `skip`, `new_windows`, `reuse_goad`, or `install_goad`. |
| `enable_log_analytics_bridge` | Enables Wazuh-to-Log Analytics correlation path. |
| `create_oci_opensearch` | Optional managed OpenSearch backend. |

## Release Artifact Requirements

The ORM ZIP must include:

- Terraform root files at ZIP root.
- `terraform/modules/**`.
- Wazuh decoder, rule, and consumer assets.
- Dashboard query packs and Wazuh view definitions.
- Scripts and Ansible roles needed by post-deploy bootstrap.
- Public-safe README for Resource Manager users.

The ZIP must exclude:

- `terraform.tfvars`.
- Terraform state and lock output.
- Local OCI CLI config.
- Local SSH keys.
- Raw screenshots and browser profiles.
- Validation artifacts with environment-specific values.

## M11 Acceptance Gate: ORM Deploy Button

Gate is green only when all checks pass from a clean tenancy or clean compartment:

1. `make orm-package` creates `artifacts/orm/oci-wazuh-orm-stack.zip`.
2. The release attaches `oci-wazuh-orm-stack.zip`.
3. The README and GitHub Wiki deploy button points to that release artifact.
4. OCI Resource Manager stack creation from the button succeeds.
5. ORM plan succeeds without local profile, local tfvars, local SSH key path, or local scripts.
6. ORM apply provisions Wazuh, Linux agents, OCI log ingestion, and Log Analytics bridge.
7. Post-apply validation confirms:
   - Wazuh dashboard reachable through tunnel.
   - Wazuh API authenticates.
   - Linux agents active.
   - GOAD or Windows mode is active or explicitly skipped by selected input.
   - OCI Audit rule fires from real OCI activity.
   - VCN Flow rule fires from real VCN traffic.
   - Wazuh alerts are present in OCI Log Analytics.
8. ORM destroy removes only demo-owned OCI resources.
9. Reused GOAD or Windows hosts retain no demo-installed Wazuh agent, Sysmon service, staging files, relay artifacts, or stale Wazuh manager records.

## Implementation Work Items

| Priority | Work item | Done when |
|---|---|---|
| P0 | Resource Manager package artifact | `make orm-package` produces a clean ZIP and CI validates it. |
| P0 | ORM input schema | Stack UI exposes required variables, defaults, descriptions, and safe choices. |
| P0 | End-to-end post-apply bootstrap | Wazuh content, OCI consumers, Log Analytics bridge, and dashboards converge without manual SSH. |
| P0 | ORM validation job | A clean Resource Manager apply produces the same evidence as local `make e2e` plus log gates. |
| P0 | ORM destroy safety | Destroy validates demo ownership and reused-host cleanup. |
| P1 | Region portability | Image lookup or documented image-selection workflow works in supported regions. |
| P1 | GOAD install option | `windows_mode=install_goad` can bootstrap GOADv3 when no reusable GOAD exists. |
| P1 | Dashboard import automation | Wazuh and Log Analytics dashboards are created by the stack or post-apply bootstrap. |

