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

- `streaming`: Service Connector Hub sends OCI Audit and VCN Flow Logs to OCI Streaming; the Wazuh node runs the Python consumer and writes normalized JSON lines under `/var/ossec/logs/oci/`.
- `object_storage`: Service Connector Hub writes log batches to Object Storage; the Wazuh node polls and normalizes the objects. Use this when Streaming is not available or cost policy forbids a stream pool.
- `direct_api`: the Wazuh node polls supported OCI APIs directly. Use only for low-rate development or fallback workflows because it is less event-driven and needs tighter API throttling.
- `log_analytics_bridge`: OCI Logging and Wazuh alert data are also visible in OCI Log Analytics for cross-source dashboards and correlations.

## Log Analytics Bridge

Run `make wazuh-log-analytics` first to create the Wazuh alert custom log, Unified Agent tail configuration, Log Analytics group, and SCH connector.

Run `make log-analytics-bridge` after the Wazuh and GOAD hosts have their OCI/Management agents installed. The gate validates:

- Log Analytics namespace onboarding
- built-in source families for Linux syslog/secure, Windows Security/System/Application/Sysmon, OCI Audit, and VCN Flow Logs
- Log Analytics entities for Wazuh AIO, both Linux agents, and the five GOAD hosts

The script prints only readiness states and writes the same redacted evidence to `artifacts/validation/M8-log-analytics-bridge.txt`.

Do not create a Service Connector from a Log Analytics log group. Reuse OCI Logging log groups as Service Connector sources, then target Log Analytics or Streaming from those OCI Logging sources.

The full demo sequence and dashboard build steps are in [END_TO_END_DEMO](../END_TO_END_DEMO.md).
