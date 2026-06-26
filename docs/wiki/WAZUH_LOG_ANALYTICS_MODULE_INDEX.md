# Wazuh and OCI Log Analytics Module Index

This index links the reusable teaching modules, screenshots, guides, and validation artifacts.

## Core Docs

- [Course landing page](index.html)
- [Product capabilities](WAZUH_LOG_ANALYTICS_PRODUCT_CAPABILITIES.md)
- [Product roadmap and use cases](WAZUH_LOG_ANALYTICS_PRODUCT_ROADMAP.md)
- [Adoption guide](WAZUH_LOG_ANALYTICS_ADOPTION_GUIDE.md)
- [Learning curve and role paths](WAZUH_LOG_ANALYTICS_LEARNING_CURVE.md)
- [Learner workbook](WAZUH_LOG_ANALYTICS_LEARNER_WORKBOOK.md)
- [Glossary and FAQ](WAZUH_LOG_ANALYTICS_GLOSSARY_FAQ.md)
- [Architecture and workflows](WAZUH_LOG_ANALYTICS_ARCHITECTURE.md)
- [OCI Resource Manager deployment plan](../ORM_RESOURCE_MANAGER_DEPLOYMENT.md)
- [Security posture wiki](WAZUH_LOG_ANALYTICS_SECURITY_POSTURE.md)
- [Hands-on walkthrough](WAZUH_LOG_ANALYTICS_HANDS_ON.md)
- [Facilitator guide](WAZUH_LOG_ANALYTICS_FACILITATOR_GUIDE.md)
- [Participant handout](WAZUH_LOG_ANALYTICS_PARTICIPANT_HANDOUT.md)
- [Assessment](WAZUH_LOG_ANALYTICS_ASSESSMENT.md)
- [Query cookbook](WAZUH_LOG_ANALYTICS_QUERY_COOKBOOK.md)
- [Posture backlog template](WAZUH_LOG_ANALYTICS_POSTURE_BACKLOG_TEMPLATE.md)
- [Screenshot runbook](WAZUH_LOG_ANALYTICS_SCREENSHOT_RUNBOOK.md)
- [End-to-end demo runbook](../END_TO_END_DEMO.md)

## Lessons

Use [Learning Curve and Role Paths](WAZUH_LOG_ANALYTICS_LEARNING_CURVE.md) to choose the right route for SOC analysts, cloud security engineers, detection engineers, platform owners, and security leaders.
Use [Learner Workbook](WAZUH_LOG_ANALYTICS_LEARNER_WORKBOOK.md) to capture evidence during a workshop or self-paced lab.

| Lesson | Topic | Primary output |
|---|---|---|
| [0001](../../lessons/0001-siem-correlation-loop.html) | SIEM correlation loop | One dashboard row tied to one security question |
| [0002](../../lessons/0002-build-security-dashboards.html) | Wazuh and Log Analytics dashboards | Saved searches and dashboard panels |
| [0003](../../lessons/0003-investigate-cloud-endpoint-network.html) | Investigation drill | Three-line investigation note |
| [0004](../../lessons/0004-turn-detections-into-posture-backlog.html) | Posture backlog | Three remediation items with verification |
| [0005](../../lessons/0005-troubleshoot-ingestion-and-dashboards.html) | Troubleshooting ingestion | Failure note and first red gate |
| [0006](../../lessons/0006-enterprise-rollout-and-governance.html) | Enterprise rollout | One-page rollout charter |
| [0007](../../lessons/0007-detection-engineering-lifecycle.html) | Detection engineering lifecycle | Detection lifecycle card |
| [0008](../../lessons/0008-executive-reporting-and-metrics.html) | Executive reporting and metrics | One-slide posture summary |

## Screenshots

| Screenshot | Use |
|---|---|
| [Wazuh login](assets/wazuh-login.png) | Show tunnel-only dashboard access |
| [Authenticated Wazuh overview](assets/wazuh-authenticated-overview-sanitized.png) | Show active Wazuh modules with live volumes redacted |
| [Live Wazuh overview](assets/wazuh-overview-live.png) | Confirm active agents and last-24-hour severity distribution |
| [Wazuh threat hunting dashboard](assets/wazuh-threat-hunting-dashboard.png) | Show alert volume, severity, authentication, MITRE, and top-agent widgets |
| [Wazuh MITRE ATT&CK dashboard](assets/wazuh-mitre-dashboard.png) | Show tactic and technique coverage by time and agent |
| [Wazuh MITRE ATT&CK events](assets/wazuh-mitre-events.png) | Validate MITRE-tagged alert rows and drill-down fields |
| [Wazuh PCI DSS dashboard](assets/wazuh-pci-dss-dashboard.png) | Show PCI DSS compliance rollups from Wazuh alerts |
| [Wazuh PCI DSS controls](assets/wazuh-pci-dss-controls.png) | Drill into PCI DSS requirements |
| [Wazuh PCI DSS events](assets/wazuh-pci-dss-events.png) | Trace PCI DSS dashboard counts to alert rows |
| [Wazuh GDPR dashboard](assets/wazuh-gdpr-dashboard.png) | Show privacy-control posture from Wazuh telemetry |
| [Wazuh HIPAA dashboard](assets/wazuh-hipaa-dashboard.png) | Show healthcare-control posture from Wazuh telemetry |
| [Wazuh HIPAA controls](assets/wazuh-hipaa-controls.png) | Drill into HIPAA requirements |
| [Wazuh NIST 800-53 dashboard](assets/wazuh-nist-800-53-dashboard.png) | Show enterprise control posture and NIST mappings |
| [OCI Log Analytics Explorer](assets/oci-log-analytics-explorer-sanitized.png) | Show source inventory with live volumes redacted |
| [Logan dashboard list](assets/logan-dashboard-list.png) | Show reusable SOC dashboard tracks |
| [Logan FIM and threat hunting](assets/logan-wazuh-fim-threat-hunting.png) | Show FIM events and top Wazuh rules |
| [Logan inventory and compliance](assets/logan-wazuh-inventory-compliance-top.png) | Show syscollector and SCA dashboard evidence |
| [Logan vulnerability severity](assets/logan-wazuh-vulnerability-severity.png) | Show vulnerability triage widgets |
| [Logan MITRE techniques](assets/logan-wazuh-mitre-techniques.png) | Show MITRE ATT&CK coverage |
| [Log Analytics dashboard errors](assets/logan-dashboard-query-errors.png) | Teach query pressure and service-error troubleshooting |
| Optional Wazuh Discover capture | Refreshed by `make auth-screenshots` when a Wazuh Discover tab is open |
| Optional Wazuh dashboard capture | Refreshed by `make auth-screenshots` when a Wazuh dashboard tab is open |
| Optional OCI Log Analytics dashboard capture | Refreshed by `make auth-screenshots` when an OCI Log Analytics dashboard tab is open |
| [Wazuh data views](assets/wazuh-discover-data-views.png) | Explain alert versus raw source records |
| [Wazuh visualization chooser](assets/wazuh-new-visualization-types.png) | Choose chart types for Wazuh dashboards |
| [Lesson 0001](assets/lesson-0001-correlation-loop.png) | Teach one correlation loop |
| [Lesson 0002](assets/lesson-0002-security-dashboards.png) | Teach dashboard construction |
| [Lesson 0003](assets/lesson-0003-investigation-drill.png) | Teach investigation pivots |
| [Lesson 0004](assets/lesson-0004-posture-backlog.png) | Teach posture backlog creation |
| [Lesson 0005](assets/lesson-0005-troubleshooting.png) | Teach ingestion troubleshooting |
| [Lesson 0006](assets/lesson-0006-enterprise-rollout.png) | Teach enterprise rollout |
| [Lesson 0007](assets/lesson-0007-detection-lifecycle.png) | Teach detection lifecycle management |
| [Lesson 0008](assets/lesson-0008-executive-metrics.png) | Teach leadership reporting |

## Validation Commands

```bash
make cap-preflight
make e2e
make goad-validate
make wazuh-content
make simulate-detections
make validate-real-oci-logs
make opensearch-oci
make validate-opensearch-oci
make wazuh-log-analytics
make log-analytics-bridge
make log-analytics-freshness
make dashboards-validate
make teach-validate
make public-pages
make down
```

## Teaching Validation

```bash
make teach-validate
make dashboards-validate
make public-pages
```

These checks cover lesson pages, wiki pages, screenshot assets, ignored raw-auth directories, redaction-sensitive patterns, local Markdown and HTML links, dashboard query packs, Wazuh view docs, and hosted public pages.

## Screenshot Commands

```bash
make auth-screenshots
```

`make auth-screenshots` expects an already-authenticated Chrome session with remote debugging on port `9223`. It writes raw screenshots to ignored local storage and committed-safe sanitized copies to `docs/wiki/assets/`.
