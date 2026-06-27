---
id: KB-OCI-WAZUH-RUNBOOK
title: OCI Wazuh Runbook
tags: [oci, wazuh, runbook, operations]
mitre: []
related: [KB-OCI-WAZUH-ARCH, KB-OCI-WAZUH-INGESTION, KB-OCI-WAZUH-DETECTIONS]
---

# OCI Wazuh Runbook

## When to use

Use this KB to deploy, operate, upgrade, rotate secrets, troubleshoot, and tear down the lab.

For the complete operator sequence, use [END_TO_END_DEMO](../END_TO_END_DEMO.md).

## SSH Timeout During Deployment

Use this procedure when `make e2e` or provisioning fails with SSH timeouts, especially:

- `ssh: connect to host <bastion> port 22: Operation timed out`
- `Connection timed out during banner exchange`
- `Connection to UNKNOWN port 65535 timed out`

The OCI-DEMO KBs identify this as a common failure mode when rapid SSH/SCP probes through a bastion trigger fail2ban or network-path rate limiting. The validation script therefore uses an SSH ControlMaster socket so Wazuh checks reuse one bastion TCP connection instead of opening a new connection per command.

Recovery steps:

1. Stop active retry loops before diagnosing. Repeated fresh SSH attempts extend the penalty window.
2. Inspect `artifacts/validation/ssh-last-error.txt` for the current failing phase (`probe=bastion` or `probe=wazuh`).
3. If the bastion probe times out, wait 2-5 minutes and retry `make e2e`. If it remains blocked, soft-reset only the bastion instance from OCI and wait until it is `RUNNING`.
4. If the Wazuh probe reports `UNKNOWN port 65535` through a stable bastion mux, soft-reset only the Wazuh instance and wait for SSH/cloud-init to settle.
5. Re-run `make e2e`; do not run parallel manual SSH loops while the gate is probing.

All M11 deployments keep Wazuh and workloads private. Validation uses the
bastion path and dashboard SSH tunnel; a bastion failure is actionable evidence,
not permission to add a direct workload rule.

For one-off content or synthetic detection gates where ControlMaster sockets become part of the failure mode, disable them for that command:

```bash
WAZUH_SSH_CONTROL=none make wazuh-content
WAZUH_SSH_CONTROL=none make simulate-detections
```

These targets use a shared SSH helper and remain idempotent. If the first SSH attempt times out, wait for the retry instead of starting another parallel SSH loop.

## Teardown

Run `make down` from this repository after confirming the target `terraform.tfvars` points to the intended compartment.
