# OCI Wazuh Detection Lab

This repository builds a reusable OCI Wazuh detection lab that can run standalone or attach to OCI-DEMO as external component Cxx.

## Operating Contract

- Use RPEQ per milestone: Research, Plan, Execute, QA.
- Prefer reuse from DevVisualization/KAG, `oci-skills`, and OCI-DEMO before authoring new modules.
- Keep all tenancy, compartment, OCID, credential, and endpoint values parameterized through `terraform.tfvars`, environment variables, or OCI Vault.
- Tag all OCI resources with `project=oci-wazuh-demo` and make teardown complete through Terraform.
- Before commits or pushes, review diffs for secrets, OCIDs, public/private topology, personal paths, and credentials.

## Milestone Gates

Gate output is written to `artifacts/validation/`. A milestone is green only when its gate exits `0`.

## Security

Never commit real OCI identifiers, Vault secret values, WinRM credentials, Wazuh passwords, private IP topology, or public IPs from internal environments. Public deployment docs must use placeholders only.
