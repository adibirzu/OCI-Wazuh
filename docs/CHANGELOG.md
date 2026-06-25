# Changelog

## Unreleased

- Added Phase 0 requirements decisions.
- Added M1 scaffold, reuse map, validation scripts, Terraform/Ansible/Wazuh layout, and KB skeletons.
- Added SSH ControlMaster validation and runbook recovery steps for bastion fail2ban/network-path timeout issues during deployment.
- Hardened Wazuh host firewall bootstrap for dashboard/API/agent ports and enabled duplicate-agent replacement in Wazuh authd.
- Configured Linux agents with a short FIM scan interval and updated E2E validation to assert manager-side syscheck alerts for both OL9 and Ubuntu agents.
- Added M5 GOAD discovery gate plus idempotent Ansible roles for Windows Wazuh agent, Sysmon, and pinned SOC Fortress Wazuh rule import.
- Added Log Analytics bridge validation for required source families and Wazuh/Linux/GOAD host entities.
- Added Wazuh alert forwarding into OCI Logging and SCH-to-Log-Analytics configuration.
- Added end-to-end demo runbook and dashboard query packs for OCI Log Analytics and Wazuh Dashboard.
- Added Wazuh OCI content deployment and synthetic OCI Audit/VCN Flow validation gates for rules `100000` and `100100`.
- Added real OCI ingestion validation: Audit API consumer, VCN Flow Log SCH-to-Streaming consumer, existing Flow Log reuse, SCH IAM policies, and `make validate-real-oci-logs`.
- Added optional OCI OpenSearch backend support plus dedicated `oci-audit-*` and `oci-flow-*` templates, data views, saved searches, and `OCI Logs Overview` dashboard creation.
- Added repeatable GOAD Wazuh install/cleanup targets and strengthened GOAD validation to require Sysmon/SOC Fortress alerts, not only active Windows agents.
- Added GOAD auto jumpbox key discovery and hub bastion relay support for overlapping/non-transitive OCI VCN topologies.
