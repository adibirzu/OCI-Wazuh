---
id: KB-OCI-WAZUH-ARCH
title: OCI Wazuh Architecture
tags: [oci, wazuh, architecture, network]
mitre: []
related: [KB-OCI-WAZUH-INGESTION, KB-OCI-WAZUH-RUNBOOK]
---

# OCI Wazuh Architecture

## When to use

Use this KB to understand topology, shapes, ports, network design, and cost guardrails for the OCI Wazuh detection lab.

## Summary

The lab deploys a Wazuh all-in-one node, two Linux agents, optional Windows/GOAD agents, OCI log ingestion, and optional Log Analytics correlation.

## Current Development Topology

- Wazuh AIO runs Wazuh `4.14.x` with dashboard/API/manager ports opened on the host firewall and restricted by OCI NSGs.
- Linux coverage includes one Oracle Linux 9 agent and one Ubuntu 24.04 agent, both enrolled and producing FIM/syscheck alerts.
- Windows coverage defaults to GOAD reuse when `make goad-discover` reports the GOAD VCN and five hosts as ready.
- Log Analytics correlation is validated with `make log-analytics-bridge`, which checks that OS, Sysmon/EDR, OCI Audit, VCN Flow, Wazuh, and GOAD entities are discoverable.

Development CAP fallback may place workloads in a public subnet for recovery from SSH/fail2ban issues. Public deployment keeps Wazuh and agents private and uses the bastion/dashboard tunnel path.

Detailed publishable architecture and workflow diagrams are maintained in [WAZUH_LOG_ANALYTICS_ARCHITECTURE](../wiki/WAZUH_LOG_ANALYTICS_ARCHITECTURE.md).
