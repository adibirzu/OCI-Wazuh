# Reuse Map

## Discovery Summary

- `localhost:5173/kag` returned the DevVisualization UI instead of JSON. Recorded in `docs/decisions/REQUIREMENTS.md`.
- DevVisualization `127.0.0.1:8000` was healthy and returned OCI-related scopes.
- `oci-skills` inventory found reusable skills for networking/compute, Resource Manager, cost, security/compliance, Events/Functions, and Log Analytics.
- OCI-DEMO discovery found existing Streaming, Service Connector Hub, GOAD event-stream, Logan field-map, and Log Analytics pipeline assets.

## Reuse Decisions

| Category | Source | Reuse Plan |
|---|---|---|
| network | `oci-skills/skills/oci-networking-compute`, OCI-DEMO C1 patterns | Reuse VCN/subnet/NSG conventions and tenancy-safety guidance; implement local Terraform modules for public reuse. |
| compute | `oci-skills/skills/oci-networking-compute`, OCI-DEMO compute helpers | Reuse shape/image parameterization patterns; implement local compute modules for Wazuh and agents. |
| logging | OCI-DEMO docs and scripts around unified stream, `shared/logan_fields.py`, `oci-skills/skills/oci-log-analytics` | Reuse field-map corrections and Log Analytics correlation guidance; implement Wazuh decoders/rules locally. |
| SCH | OCI-DEMO C3 Service Connector Hub pattern and continuous shipping docs | Reuse SCH-to-Streaming topology; add selectable Object Storage fallback. |
| streaming | OCI-DEMO unified stream and Kafka-compatible streaming docs | Reuse stream pool/stream naming and consumer auth patterns; local consumer uses OCI Python SDK by default. |
| GOAD | OCI-DEMO GOAD event stream references and GOADv3 upstream | Discover existing GOAD VCN; if absent and requested, install GOADv3 in OCI. |
| cost | `oci-skills/skills/oci-cost` | Reuse cost-estimation conventions and add lab-specific estimate script. |
| log analytics | OCI-DEMO `shared/log_analytics_pipeline.py`, `oci-skills/skills/oci-log-analytics` | Add optional bridge from host/EDR/Wazuh alert data to Log Analytics dashboards. |

## M5 GOAD Reuse Detail

- Reused OCI-DEMO `scripts/c5_install_sysmon.sh` pattern for running the GOAD Sysmon extension through the GOAD jumpbox when available.
- Reused OCI-DEMO `scripts/c16_configure_logging.sh` Windows collection model: Security, System, Application, and `Microsoft-Windows-Sysmon/Operational` channels.
- Reused OCI-DEMO `scripts/c16_configure_la_sources.sh` Log Analytics source association model for Windows Security/System/Application/Sysmon and Linux Syslog/Secure logs.
- Reused GOADv3 OCI provider host naming and target set: `braavos`, `castelblack`, `kingslanding`, `meereen`, `winterfell`.
- Live CAP discovery found GOAD reuse ready; `make goad-discover` is the repeatable redacted gate.

## Public Deployment Boundary

Local paths are development-only. Public releases must vendor/adapt the needed logic into this repository or document public upstream dependencies.
