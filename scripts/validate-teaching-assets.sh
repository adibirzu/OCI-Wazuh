#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

required_files=(
  "docs/wiki/WAZUH_LOG_ANALYTICS_MODULE_INDEX.md"
  "docs/wiki/WAZUH_LOG_ANALYTICS_SECURITY_POSTURE.md"
  "docs/wiki/WAZUH_LOG_ANALYTICS_HANDS_ON.md"
  "docs/wiki/WAZUH_LOG_ANALYTICS_FACILITATOR_GUIDE.md"
  "docs/wiki/WAZUH_LOG_ANALYTICS_ASSESSMENT.md"
  "docs/wiki/WAZUH_LOG_ANALYTICS_QUERY_COOKBOOK.md"
  "docs/wiki/WAZUH_LOG_ANALYTICS_POSTURE_BACKLOG_TEMPLATE.md"
  "docs/wiki/assets/wazuh-authenticated-overview-sanitized.png"
  "docs/wiki/assets/oci-log-analytics-explorer-sanitized.png"
  "docs/wiki/assets/wazuh-login.png"
  "docs/wiki/assets/wazuh-discover-data-views.png"
  "docs/wiki/assets/wazuh-new-visualization-types.png"
  "reference/0001-wazuh-log-analytics-security-posture.html"
)

for lesson in lessons/000{1..8}-*.html; do
  required_files+=("${lesson}")
done

for file in "${required_files[@]}"; do
  if [[ ! -s "${file}" ]]; then
    echo "missing_or_empty=${file}" >&2
    exit 1
  fi
done

if ! git check-ignore -q docs/wiki/assets/live/; then
  echo "raw_live_screenshot_dir_not_ignored=docs/wiki/assets/live/" >&2
  exit 1
fi

if ! git check-ignore -q .tmp-chrome-auth-profile/; then
  echo "chrome_auth_profile_not_ignored=.tmp-chrome-auth-profile/" >&2
  exit 1
fi

namespace_a="fr4zqfi""muxtr"
namespace_b="aaaadhp5ewo4eaaaa""aaaafs7q"
namespace_c="axfo51""x8x2ap"
namespace_d="axoxdiev""da5j"
demo_password_fragment="em4QcVQlHvpTV""Y68"
redaction_pattern="ocid1\\.|130\\.61\\.|161\\.153\\.|144\\.24\\.|129\\.153\\.|141\\.147\\.|82\\.77\\.|109\\.166\\.|${namespace_a}|${namespace_b}|${namespace_c}|${namespace_d}|${demo_password_fragment}"

if rg -n "${redaction_pattern}" \
  --glob '!scripts/validate-teaching-assets.sh' \
  docs/wiki assets lessons reference MISSION.md RESOURCES.md NOTES.md learning-records .gitignore scripts; then
  echo "redaction_scan=failed" >&2
  exit 1
fi

echo "teaching_assets=ready"
echo "lessons=8"
echo "wiki_docs=7"
