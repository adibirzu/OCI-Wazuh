# Security Policy

## Scope

This repository is a deployable OCI security demo. Treat all tenant details, generated credentials, Terraform state, screenshots, and runtime artifacts as sensitive unless they are already sanitized examples committed to the repository.

## Reporting a Vulnerability

Do not open a public issue for suspected credential exposure, tenant topology exposure, privilege escalation, destructive teardown gaps, or bypasses in the validation scripts.

Use GitHub private vulnerability reporting when available for this repository, or contact the repository owner through GitHub with a short summary and a safe reproduction path.

Include:

- affected commit or release tag,
- affected component,
- impact,
- minimal reproduction steps,
- whether any real credential, OCID, IP address, tenancy namespace, screenshot, or Terraform state was exposed.

Do not include real secrets, private keys, tenancy OCIDs, public/private IP addresses, API key fingerprints, Terraform state, raw authenticated screenshots, or live tenant logs in the report body.

## Public-Safe Redaction Rules

Before sharing logs, issues, screenshots, or pull requests, redact:

- OCI identifiers such as tenancy, compartment, subnet, VNIC, instance, log group, Log Analytics, and user OCIDs,
- public and private IP addresses from deployed environments,
- API key fingerprints, private keys, passwords, Vault secret names that reveal structure, and session tokens,
- tenancy namespaces and registry names,
- Terraform state and `terraform.tfvars`,
- raw authenticated Wazuh, OpenSearch, or OCI Console screenshots.

Use placeholders such as `<TENANCY_OCID>`, `<COMPARTMENT_OCID>`, `<WAZUH_PUBLIC_IP>`, `<PRIVATE_IP>`, `<LA_NAMESPACE>`, and `<SECRET_NAME>`.

## Validation Before Publishing Changes

Run these checks before opening a PR:

```bash
make lint
make teach-validate
gitleaks detect --source . --redact --exit-code 1
```

For changes touching Terraform, Ansible, OCI credentials, ingestion, Wazuh rules, OpenSearch, Log Analytics, GOAD cleanup, or teardown behavior, also run the narrow validation target documented beside that component.
