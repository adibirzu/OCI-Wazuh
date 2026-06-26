# Wazuh and OCI Log Analytics Screenshot Runbook

Use this runbook to refresh authenticated screenshots for the teaching wiki without committing raw tenant data.

## Rules

- Raw authenticated screenshots stay in `docs/wiki/assets/live/`; this directory is ignored.
- Browser authentication state stays in `.tmp-chrome-auth-profile/`; this directory is ignored.
- Commit only sanitized screenshots under `docs/wiki/assets/`.
- Inspect every screenshot before committing.
- Run `make teach-validate` before committing.

## Open Authenticated Browser

Start Chrome with remote debugging and an isolated local profile:

```bash
open -na "Google Chrome" --args \
  --remote-debugging-port=9223 \
  --user-data-dir=/Users/abirzu/dev/OCI-Wazuh/.tmp-chrome-auth-profile \
  --ignore-certificate-errors \
  https://127.0.0.1:8443/app/login \
  'https://cloud.oracle.com/loganalytics/explorer?region=eu-frankfurt-1'
```

Authenticate to:

- Wazuh Dashboard through the local tunnel.
- OCI Console Log Analytics Explorer.

For a richer lab guide, open these tabs before capture:

- Wazuh overview or modules page.
- Wazuh Discover with `wazuh-alerts-*`, `oci-audit-*`, or `oci-flow-*`.
- Wazuh `OCI Logs Overview` dashboard.
- OCI Log Analytics Log Explorer with source inventory.
- OCI Log Analytics dashboard for Wazuh and OCI correlation.

## Capture and Sanitize

```bash
make auth-screenshots
```

The command writes:

```text
docs/wiki/assets/live/wazuh-authenticated-overview.png
docs/wiki/assets/live/oci-log-analytics-explorer.png
docs/wiki/assets/live/wazuh-discover-live.png
docs/wiki/assets/live/wazuh-dashboard-live.png
docs/wiki/assets/live/oci-log-analytics-dashboard-live.png
docs/wiki/assets/wazuh-authenticated-overview-sanitized.png
docs/wiki/assets/oci-log-analytics-explorer-sanitized.png
docs/wiki/assets/wazuh-discover-live-sanitized.png
docs/wiki/assets/wazuh-dashboard-live-sanitized.png
docs/wiki/assets/oci-log-analytics-dashboard-live-sanitized.png
```

The optional files are created only when matching authenticated tabs are open. Only sanitized files should be committed.

## Validate

```bash
make teach-validate
make lint
make dashboards-validate
```

`make teach-validate` checks that required lesson/wiki assets exist, raw screenshot directories are ignored, auth profiles are ignored, and redaction-sensitive text patterns are absent.

## Commit

```bash
git add docs/wiki/assets/wazuh-authenticated-overview-sanitized.png \
  docs/wiki/assets/oci-log-analytics-explorer-sanitized.png \
  docs/wiki/assets/wazuh-discover-live-sanitized.png \
  docs/wiki/assets/wazuh-dashboard-live-sanitized.png \
  docs/wiki/assets/oci-log-analytics-dashboard-live-sanitized.png \
  docs/wiki/WAZUH_LOG_ANALYTICS_*.md \
  scripts/capture-authenticated-screenshots.* \
  scripts/sanitize-dashboard-screenshots.py \
  scripts/validate-teaching-assets.sh \
  Makefile README.md .gitignore
git commit -m "docs: refresh Wazuh teaching screenshots"
```
