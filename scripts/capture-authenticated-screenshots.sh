#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROME_DEBUG_PORT="${CHROME_DEBUG_PORT:-9223}"
DEBUG_URL="http://127.0.0.1:${CHROME_DEBUG_PORT}/json/version"

if ! curl -fsS "${DEBUG_URL}" >/dev/null; then
  cat >&2 <<EOF
Chrome remote debugging is not reachable at ${DEBUG_URL}.

Open an authenticated browser first:

open -na "Google Chrome" --args \\
  --remote-debugging-port=${CHROME_DEBUG_PORT} \\
  --user-data-dir=${ROOT_DIR}/.tmp-chrome-auth-profile \\
  --ignore-certificate-errors \\
  https://127.0.0.1:8443/app/login \\
  'https://cloud.oracle.com/loganalytics/explorer?region=eu-frankfurt-1'

Then authenticate to Wazuh and OCI Log Analytics and rerun this script.
EOF
  exit 1
fi

node "${ROOT_DIR}/scripts/capture-authenticated-screenshots.js"
python3 "${ROOT_DIR}/scripts/sanitize-dashboard-screenshots.py"

echo "authenticated_screenshots=ready"
echo "raw_live_dir=docs/wiki/assets/live"
echo "sanitized_wazuh=docs/wiki/assets/wazuh-authenticated-overview-sanitized.png"
echo "sanitized_oci=docs/wiki/assets/oci-log-analytics-explorer-sanitized.png"
