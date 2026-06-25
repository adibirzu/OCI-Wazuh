# Mission: Wazuh and OCI Log Analytics Security Posture

## Why

Build a repeatable learning path that shows security teams how to combine Wazuh endpoint detections, OCI Audit, VCN Flow Logs, operating-system logs, Windows Sysmon, and OCI Log Analytics dashboards into one practical posture-improvement workflow.

## Success looks like

- Explain which telemetry belongs in Wazuh, which belongs in OCI Log Analytics, and where both should be correlated.
- Build Wazuh views for OCI Audit, VCN Flow, Linux FIM/SCA, and GOAD Windows/Sysmon detections.
- Build OCI Log Analytics dashboards that correlate Wazuh alerts with cloud, network, OS, and EDR-style telemetry.
- Use ATT&CK-mapped detections and dashboard gaps to prioritize concrete hardening work.
- Deploy, validate, and tear down the OCI Wazuh demo without committing secrets or tenant-specific identifiers.

## Constraints

- Use public, reusable content in committed material.
- Do not include real OCIDs, IPs, credentials, tenancy namespaces, or internal topology.
- Prefer official Wazuh, Oracle, and MITRE documentation for concepts.
- Keep modules hands-on and tied to the existing demo commands in this repository.

## Out of scope

- Replacing a complete SOC operating model.
- Vendor-comparison content.
- Tenant-specific CAP screenshots, credentials, or private run history.
