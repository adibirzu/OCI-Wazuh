# Contributing

This project should remain reusable outside a single tenancy. Keep changes parameterized, idempotent, public-safe, and fully tear-downable.

## Development Flow

1. Create a feature branch.
2. Keep tenant-specific values in local environment variables, OCI Vault, or `terraform/terraform.tfvars`.
3. Update the relevant docs or KB when behavior changes.
4. Run validation before opening a PR.

```bash
make lint
make teach-validate
```

For deployment-affecting changes, run the relevant target:

```bash
make bootstrap
make e2e
make goad-validate
make wazuh-content
make validate-real-oci-logs
make validate-opensearch-oci
make log-analytics-bridge
```

## Security and Redaction

Never commit:

- real OCIDs,
- public or private IP addresses from a live environment,
- API key fingerprints or private keys,
- Terraform state or `terraform.tfvars`,
- Vault material,
- Wazuh, OpenSearch, OCI Console, or Log Analytics raw authenticated screenshots,
- live tenant logs that identify an environment.

Use sanitized examples and placeholders instead.

## Documentation Expectations

Changes to architecture, deployment flow, ingestion modes, detections, dashboards, GOAD reuse, or teardown should update at least one of:

- `README.md`
- `docs/END_TO_END_DEMO.md`
- `docs/kb/`
- `docs/wiki/`
- `dashboards/`

## Pull Request Checklist

- [ ] Change is parameterized and has no hardcoded tenancy data.
- [ ] Teardown behavior is preserved or updated in documentation.
- [ ] Public docs avoid real OCIDs, IPs, credentials, and raw screenshots.
- [ ] `make lint` passes.
- [ ] `make teach-validate` passes.
- [ ] Security-sensitive changes include a focused validation note.
