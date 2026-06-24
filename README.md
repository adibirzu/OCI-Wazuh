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
make simulate-detections
make validate-real-oci-logs
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

## Ingestion Modes

- `streaming`: VCN Flow Logs from OCI Logging through Service Connector Hub to OCI Streaming, consumed by the Wazuh node. OCI Audit is collected from the real OCI Audit API by the Wazuh node.
- `object_storage`: VCN Flow Logs from Service Connector Hub to Object Storage, polled by the Wazuh node. OCI Audit still uses the Audit API path.
- `direct_api`: Audit-only fallback for development or restricted tenancies.
- `log_analytics_bridge`: OS/EDR/Wazuh alerts also sent to OCI Log Analytics for correlation dashboards.

The default development path is `streaming`.

## Dashboards

- OCI Log Analytics query pack: [dashboards/log-analytics/oci-wazuh-dashboard-queries.json](dashboards/log-analytics/oci-wazuh-dashboard-queries.json)
- Wazuh saved-search/view guide: [dashboards/wazuh/oci-wazuh-views.md](dashboards/wazuh/oci-wazuh-views.md)
