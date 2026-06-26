# Plan

## RPEQ Milestones

M1 bootstrap/discovery is implemented by `make bootstrap`.

M2-M10 are represented by Terraform modules, Ansible playbooks, Wazuh packs, scripts, and KBs in this repo. Each milestone will harden the corresponding module and gate until green against a real tenancy.

## Current Gate

Run:

```bash
make bootstrap
```

## M11 — OCI Resource Manager Deploy Button

Goal: publish a one-click OCI Resource Manager deployment button that can deploy the full lab end to end, not only the Terraform base layer.

Deploy button target:

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/adibirzu/OCI-Wazuh/releases/latest/download/oci-wazuh-orm-stack.zip)

Tracked plan: [ORM Resource Manager deployment](ORM_RESOURCE_MANAGER_DEPLOYMENT.md).

Required scope:

- Wazuh 4.14.x all-in-one deployment.
- Linux agents enrolled and validated.
- Windows path selectable: skip, new Windows Server, reuse GOAD, or install GOADv3 when supported.
- OCI Audit and VCN Flow Logs ingested into Wazuh with custom rules.
- Wazuh alert forwarding into OCI Log Analytics.
- Dedicated OpenSearch views for Wazuh alerts, OCI Audit, and VCN Flow records.
- Safe destroy with reused-host cleanup.

Gate:

```bash
make orm-package
```

Then create a clean OCI Resource Manager stack from the release ZIP, apply it, run the same evidence checks as `make e2e`, `make validate-real-oci-logs`, `make log-analytics-freshness`, and destroy it with no residual demo resources.
