# Wazuh and OCI Log Analytics Module Index

This index links the reusable teaching modules, screenshots, guides, and validation artifacts.

## Core Docs

- [Course landing page](index.html)
- [Architecture and workflows](WAZUH_LOG_ANALYTICS_ARCHITECTURE.md)
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
| [OCI Log Analytics Explorer](assets/oci-log-analytics-explorer-sanitized.png) | Show source inventory with live volumes redacted |
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
make down
```

## Teaching Validation

```bash
make teach-validate
```

This checks the required lesson pages, wiki pages, screenshot assets, ignored raw-auth directories, and redaction-sensitive patterns.
It also validates local Markdown and HTML links used by the teaching pack.

## Screenshot Commands

```bash
make auth-screenshots
```

`make auth-screenshots` expects an already-authenticated Chrome session with remote debugging on port `9223`. It writes raw screenshots to ignored local storage and committed-safe sanitized copies to `docs/wiki/assets/`.
