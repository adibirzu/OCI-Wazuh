# OCI Wazuh Detection Lab

Standalone and OCI-DEMO attachable Wazuh 4.14.x detection lab for OCI.

## Quickstart

For the complete deploy/demo/teardown path, use [docs/END_TO_END_DEMO.md](docs/END_TO_END_DEMO.md).

```bash
make bootstrap
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# edit terraform/terraform.tfvars
make up
make e2e
make goad-discover
make wazuh-log-analytics
make log-analytics-bridge
make wazuh-content
make opensearch-oci
make goad-up
make goad-validate
make simulate-detections
make validate-real-oci-logs
make validate-opensearch-oci
```

If the development tenant rate-limits repeated SSH probes, prefer the default SSH ControlMaster path and wait 2-5 minutes before retrying. Use `WAZUH_SSH_CONTROL=none` only for isolated debugging.

## OCI-DEMO Attach

OCI-DEMO should add this repository as `external/oci-wazuh-demo` and expose a passthrough target:

```bash
make wazuh-demo-up
```

## Teardown

```bash
make down
```

`make down` runs `make goad-down` first. For reused GOAD hosts this removes the Wazuh Windows agent, Sysmon service, staging files, and Wazuh manager agent records before Terraform destroys demo-owned OCI resources.

## Ingestion Modes

- `streaming`: VCN Flow Logs from OCI Logging through Service Connector Hub to OCI Streaming, consumed by the Wazuh node. OCI Audit is collected from the real OCI Audit API by the Wazuh node.
- `object_storage`: VCN Flow Logs from Service Connector Hub to Object Storage, polled by the Wazuh node. OCI Audit still uses the Audit API path.
- `direct_api`: Audit-only fallback for development or restricted tenancies.
- `log_analytics_bridge`: OS/EDR/Wazuh alerts also sent to OCI Log Analytics for correlation dashboards.

The default development path is `streaming`.

## OpenSearch Backend

The default backend is the Wazuh all-in-one OpenSearch indexer. Run:

```bash
make opensearch-oci
make validate-opensearch-oci
```

This creates index templates, data views, saved searches, and the `OCI Logs Overview` dashboard for dedicated `oci-audit-*` and `oci-flow-*` indices.

To use OCI Search Service with OpenSearch instead of the AIO indexer, either provide an existing endpoint:

```bash
OCI_WAZUH_OPENSEARCH_BACKEND=oci_opensearch \
OCI_WAZUH_OPENSEARCH_URL=https://<OPENSEARCH_ENDPOINT>:9200 \
OCI_WAZUH_DASHBOARD_URL=https://<OPENSEARCH_DASHBOARD_ENDPOINT>:5601 \
OCI_WAZUH_OPENSEARCH_USERNAME=<USER> \
OCI_WAZUH_OPENSEARCH_PASSWORD=<PASSWORD> \
make opensearch-oci
```

or set `create_oci_opensearch = true` in local `terraform/terraform.tfvars` and keep the master password/hash only in local tfvars, environment variables, or OCI Vault.

## Dashboards

- OCI Log Analytics query pack: [dashboards/log-analytics/oci-wazuh-dashboard-queries.json](dashboards/log-analytics/oci-wazuh-dashboard-queries.json)
- Wazuh saved-search/view guide: [dashboards/wazuh/oci-wazuh-views.md](dashboards/wazuh/oci-wazuh-views.md)

## Teaching Wiki

Use the course pack when presenting Wazuh and OCI Log Analytics as a company security-posture demo:

- Hosted documentation: https://adibirzu.github.io/OCI-Wazuh/
- Product capabilities: [docs/wiki/WAZUH_LOG_ANALYTICS_PRODUCT_CAPABILITIES.md](docs/wiki/WAZUH_LOG_ANALYTICS_PRODUCT_CAPABILITIES.md)
- Product roadmap and use cases: [docs/wiki/WAZUH_LOG_ANALYTICS_PRODUCT_ROADMAP.md](docs/wiki/WAZUH_LOG_ANALYTICS_PRODUCT_ROADMAP.md)
- Learning curve and role paths: [docs/wiki/WAZUH_LOG_ANALYTICS_LEARNING_CURVE.md](docs/wiki/WAZUH_LOG_ANALYTICS_LEARNING_CURVE.md)
- Learner workbook: [docs/wiki/WAZUH_LOG_ANALYTICS_LEARNER_WORKBOOK.md](docs/wiki/WAZUH_LOG_ANALYTICS_LEARNER_WORKBOOK.md)
- Module index: [docs/wiki/WAZUH_LOG_ANALYTICS_MODULE_INDEX.md](docs/wiki/WAZUH_LOG_ANALYTICS_MODULE_INDEX.md)
- Architecture and workflows: [docs/wiki/WAZUH_LOG_ANALYTICS_ARCHITECTURE.md](docs/wiki/WAZUH_LOG_ANALYTICS_ARCHITECTURE.md)
- Browser landing page: [docs/wiki/index.html](docs/wiki/index.html)
- Hands-on walkthrough: [docs/wiki/WAZUH_LOG_ANALYTICS_HANDS_ON.md](docs/wiki/WAZUH_LOG_ANALYTICS_HANDS_ON.md)
- Facilitator guide: [docs/wiki/WAZUH_LOG_ANALYTICS_FACILITATOR_GUIDE.md](docs/wiki/WAZUH_LOG_ANALYTICS_FACILITATOR_GUIDE.md)
- Participant handout: [docs/wiki/WAZUH_LOG_ANALYTICS_PARTICIPANT_HANDOUT.md](docs/wiki/WAZUH_LOG_ANALYTICS_PARTICIPANT_HANDOUT.md)
- Query cookbook: [docs/wiki/WAZUH_LOG_ANALYTICS_QUERY_COOKBOOK.md](docs/wiki/WAZUH_LOG_ANALYTICS_QUERY_COOKBOOK.md)
- Assessment: [docs/wiki/WAZUH_LOG_ANALYTICS_ASSESSMENT.md](docs/wiki/WAZUH_LOG_ANALYTICS_ASSESSMENT.md)

Validate the teaching material:

```bash
make teach-validate
```

Refresh authenticated screenshots after logging in to Wazuh and OCI Log Analytics:

```bash
make auth-screenshots
```

The raw authenticated screenshots and browser profile stay ignored; only sanitized screenshots under `docs/wiki/assets/` should be committed.
