---
id: KB-OCI-WAZUH-INGESTION
title: OCI Wazuh Ingestion
tags: [oci, wazuh, logging, streaming, service-connector, log-analytics]
mitre: [T1046, T1078]
related: [KB-OCI-WAZUH-DETECTIONS, KB-OCI-WAZUH-RUNBOOK]
---

# OCI Wazuh Ingestion

## When to use

Use this KB to select and operate OCI Audit, VCN Flow Log, OS, EDR, and Wazuh alert ingestion paths.

## Options

- `streaming`: Service Connector Hub sends VCN Flow Logs from OCI Logging to OCI Streaming; the Wazuh node consumes the stream and writes normalized JSON lines under `/var/ossec/logs/oci/flow.json`. OCI Audit uses the real OCI Audit API consumer in parallel.
- `object_storage`: Service Connector Hub writes VCN Flow Log batches to Object Storage; the Wazuh node polls and normalizes the objects. OCI Audit still uses the Audit API path. Use this when Streaming is not available or cost policy forbids a stream pool.
- `direct_api`: Audit-only fallback. The Wazuh node polls OCI Audit directly and writes `/var/ossec/logs/oci/audit.json`.
- `log_analytics_bridge`: OCI Logging and Wazuh alert data are also visible in OCI Log Analytics for cross-source dashboards and correlations.

OCI Audit is not modeled as an OCI Logging service source in the active OCI catalog used by this lab. The reusable implementation therefore treats Audit as an API source and VCN Flow as a Logging/SCH source.

## Existing Flow Log Reuse

OCI allows one active Flow Log configuration per resource/category combination. If a subnet, VCN, or VNIC already has Flow Logs enabled, set `existing_flow_logs` in local `terraform.tfvars` with the source compartment, log group, and log OCID. Terraform then skips Flow Log creation and creates the SCH permissions/connector to reuse that source.

For new deployments, leave `existing_flow_logs = []` and set `flow_log_resource_ids` to the subnet, VCN, or VNIC OCIDs to monitor. Subnet, VCN, and VNIC OCIDs are mapped to the correct Flow Log categories automatically.

## Real Validation

`make simulate-detections` validates Wazuh decoder/rule behavior with local normalized JSON.

`make validate-real-oci-logs` validates the live tenancy path by creating/deleting a temporary tag namespace and generating denied network traffic. The gate passes only when Wazuh raises Audit rule `100000` and Flow rule `100100` from real OCI telemetry.

## Log Analytics Bridge

Run `make wazuh-log-analytics` first to create the Wazuh alert custom log, Unified Agent tail configuration, Log Analytics group, and SCH connector.

Run `make log-analytics-bridge` after the Wazuh and GOAD hosts have their OCI/Management agents installed. The gate validates:

- Log Analytics namespace onboarding
- built-in source families for Linux syslog/secure, Windows Security/System/Application/Sysmon, OCI Audit, and VCN Flow Logs
- Log Analytics entities for Wazuh AIO, both Linux agents, and the five GOAD hosts

The script prints only readiness states and writes the same redacted evidence to `artifacts/validation/M8-log-analytics-bridge.txt`.

Do not create a Service Connector from a Log Analytics log group. Reuse OCI Logging log groups as Service Connector sources, then target Log Analytics or Streaming from those OCI Logging sources.

The full demo sequence and dashboard build steps are in [END_TO_END_DEMO](../END_TO_END_DEMO.md).
