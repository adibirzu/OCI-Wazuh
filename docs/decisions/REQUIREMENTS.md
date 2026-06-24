# Requirements Decisions

Date: 2026-06-23

## Phase 0 Answers

1. Region defaults to `eu-frankfurt-1`, but users may choose any OCI region through Terraform variables. The lab discovers an existing GOAD VCN and reuses/peers it when present. If GOAD is absent and Windows detections are requested, deploy GOADv3 in OCI from `https://github.com/adibirzu/GOADv3`.
2. Wazuh topology is all-in-one on `VM.Standard.E5.Flex`, 4 OCPU, 16 GB memory, 200 GB block volume.
3. Unattended Windows path reuses GOAD if reachable from the new VCN; otherwise it skips Windows and logs a notice.
4. GOAD is expected to be running when reused, with WinRM/domain-admin credentials in OCI Vault under prefix `goad/`.
5. Primary OCI ingestion path is Service Connector Hub to OCI Streaming to Python consumer on the Wazuh host to Wazuh logcollector. Additional supported options must be documented and implemented as selectable modes: SCH to Object Storage polling fallback, direct OCI API polling for Audit/Logging where appropriate, and Log Analytics bridge for OS/EDR/Wazuh alert correlation.
6. Development reuse sources are OCI-DEMO modules and scripts for network, compute, logging, service connector, streaming, Logan field maps, and Log Analytics patterns. Public deployment must depend only on public code/data or code copied into this repository with appropriate attribution.
7. Development repo paths are `/Users/abirzu/dev/OCI-DEMO` and `/Users/abirzu/dev/oci-skills`. Public deployment must not depend on those local paths.
8. DevVisualization is running for development discovery. The documented `localhost:5173/kag` endpoint served the UI during discovery, so development uses the working API on `127.0.0.1:8000`. Public deployment must not require DevVisualization.
9. OCI-DEMO integration is a submodule at `external/oci-wazuh-demo` with a top-level `make wazuh-demo-up` passthrough. Standalone `make up` remains unchanged. The component will be registered as a Cxx component in OCI-DEMO.
10. State backend is OCI Object Storage. Secrets are in OCI Vault. Guardrails include tags, `cost-estimate.sh`, and optional scheduled teardown.

## Log Analytics Extension

The solution must also support forwarding Linux OS logs, Windows/Sysmon EDR data, and Wazuh alerts into OCI Log Analytics, with dashboards that correlate OCI Audit, VCN Flow Logs, host OS logs, Sysmon/EDR events, and Wazuh alerts.
