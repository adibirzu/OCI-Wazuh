# Wazuh and OCI Log Analytics Security Posture Resources

## Knowledge

- [Wazuh: Log data collection](https://documentation.wazuh.com/current/user-manual/capabilities/log-data-collection/index.html)
  Use for Wazuh logcollector behavior, local file monitoring, syslog collection, journald collection, and OS-specific log collection.
- [Wazuh: Data analysis, decoders, and rules](https://documentation.wazuh.com/current/user-manual/ruleset/index.html)
  Use for custom decoder/rule design, rule testing, XML syntax, and ATT&CK mapping inside Wazuh detections.
- [Wazuh: File integrity monitoring](https://documentation.wazuh.com/current/user-manual/capabilities/file-integrity/index.html)
  Use for Linux and Windows FIM posture modules, integrity-change alerts, and persistence-detection examples.
- [Wazuh: Security Configuration Assessment](https://documentation.wazuh.com/current/user-manual/capabilities/sec-config-assessment/index.html)
  Use for SCA checks, hardening posture, compliance evidence, and drift tracking.
- [Wazuh: Vulnerability detection](https://documentation.wazuh.com/current/user-manual/capabilities/vulnerability-detection/index.html)
  Use for package inventory, vulnerability posture, and remediation prioritization modules.
- [Oracle: Log Analytics](https://docs.oracle.com/en-us/iaas/log-analytics/home.htm)
  Use for Log Analytics ingestion options, search, visualization, dashboards, entities, sources, parsers, and alerts.
- [Oracle: Audit overview](https://docs.oracle.com/en-us/iaas/Content/Audit/Concepts/auditoverview.htm)
  Use for cloud control-plane audit semantics, event fields, and supported access paths.
- [Oracle: VCN Flow Logs](https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/vcn_flow_logs.htm)
  Use for network-flow security analytics, accepted/rejected traffic, ports, protocols, and flow-based detections.
- [Oracle: Connector Hub](https://docs.oracle.com/en-us/iaas/Content/connector-hub/overview.htm)
  Use for OCI service-to-service routing between Logging, Streaming, Object Storage, Log Analytics, Notifications, and Functions.
- [MITRE ATT&CK Enterprise Matrix](https://attack.mitre.org/matrices/enterprise/)
  Use for detection coverage, technique mapping, gap analysis, and explaining posture improvements in adversary-behavior terms.
- [Project runbook: OCI Wazuh End-to-End Demo](docs/END_TO_END_DEMO.md)
  Use for the tested local commands that deploy Wazuh, enroll Linux and GOAD agents, validate real OCI logs, publish Wazuh alerts to Log Analytics, and tear down.
- [Project KB: OCI Wazuh Ingestion](docs/kb/KB-OCI-WAZUH-INGESTION.md)
  Use for this repository's ingestion choices: Streaming, Object Storage fallback, direct Audit API, dedicated OpenSearch indices, and Log Analytics bridge.

## Wisdom (Communities)

- [Wazuh Community](https://wazuh.com/community/)
  Use for product-specific operational questions, agent behavior, ruleset patterns, and upgrade notes.
- [Oracle Cloud Customer Connect](https://community.oracle.com/customerconnect/categories/cloud-infrastructure)
  Use for OCI service behavior, Log Analytics questions, tenancy-specific product guidance, and known issues.
- [MITRE ATT&CK Community](https://attack.mitre.org/resources/)
  Use for ATT&CK methodology, detection coverage language, and technique taxonomy updates.

## Gaps

- Public examples for Wazuh alerts flowing into OCI Log Analytics are limited. Treat this repository's runbook and dashboard query pack as the primary implementation reference.
- Log Analytics source names can vary by tenancy. Always run source discovery before teaching or saving OCL queries for a new environment.
