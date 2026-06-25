---
id: KB-OCI-WAZUH-GOAD
title: OCI Wazuh GOAD Reuse
tags: [oci, wazuh, goad, windows, sysmon]
mitre: [T1110, T1059]
related: [KB-OCI-WAZUH-DETECTIONS, KB-OCI-WAZUH-RUNBOOK]
---

# OCI Wazuh GOAD Reuse

## When to use

Use this KB when adding Wazuh agent, Sysmon, and SOC Fortress rules to existing GOAD hosts or installing GOADv3 in OCI.

## Hosts

The expected GOAD hosts are `braavos`, `castelblack`, `kingslanding`, `meereen`, and `winterfell`.

## Reuse Path

Run `make goad-discover` first. The gate reads the OCI profile and compartment from `terraform/terraform.tfvars` or environment variables, finds an available GOAD VCN, and verifies that the five expected hosts are `RUNNING`. It writes redacted evidence to `artifacts/validation/M5-goad-discovery.txt`.

When GOAD reuse is ready, run `ansible/playbooks/goad-reuse.yml` with:

- a `wazuh_manager` host that can SSH to the Wazuh manager
- a `goad_hosts` Windows group reachable over WinRM
- `wazuh_manager_ip` set to the Wazuh manager private IP

The playbook imports SOC Fortress rules once on the Wazuh manager, then installs or updates the Wazuh Windows agent and Sysmon on each GOAD host.

The preferred wrapper is:

```bash
make goad-up
make goad-validate
```

`make goad-up` builds a temporary WinRM inventory in `artifacts/validation/`, creates or reuses a single SSH tunnel, installs the Wazuh agent and Sysmon on all five hosts, and imports SOC Fortress rules on the Wazuh manager. In `auto` mode it discovers the running GOAD jumpbox key from OCI metadata when a local matching private key exists. If direct Wazuh-to-GOAD routing is unavailable because OCI LPG routing is non-transitive or the VCNs cannot be directly peered, the script configures the hub bastion as a persistent TCP relay for Wazuh ports `1514` and `1515`; Windows agents then use the bastion private IP as their manager endpoint.

`make goad-validate` requires both:

- all five GOAD agents are `Active` in Wazuh
- at least one GOAD Sysmon/SOC Fortress-style alert is present in `/var/ossec/logs/alerts/alerts.json`

## Pinned Content

- Wazuh Windows agent: `4.14.5-1`
- Sysmon config: `olafhartong/sysmon-modular` commit `a9ff298f6d228c181be71b213c73d111c6096f41`
- SOC Fortress rules: `socfortress/Wazuh-Rules` commit `66b70d6a380b2cffb625801da0b0ccb1933ed95d`

## OCI-DEMO Reuse Notes

The implementation follows OCI-DEMO C5/C16 patterns:

- run Sysmon through the GOAD jumpbox when the existing GOAD extension is present
- collect Windows Security, System, Application, and `Microsoft-Windows-Sysmon/Operational`
- reuse the shared GOAD OCI Logging group and Unified Agent configurations instead of creating a Service Connector from a Log Analytics log group

If `make goad-discover` reports `goad_reuse=not_ready`, use the GOADv3 OCI provider path and re-run discovery after deployment.

## Cleanup

`make down` runs `make goad-down` before Terraform destroy. The cleanup playbook removes WazuhSvc, the Wazuh Windows package, Sysmon service, and staging directories from reused GOAD hosts, then removes the GOAD agent records from the Wazuh manager.
