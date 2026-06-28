#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"
RUNTIME="$ROOT_DIR/artifacts/runtime"
VALIDATION="$ROOT_DIR/artifacts/validation"
project="${1:?project name required}"
profile="${2:-DEFAULT}"
mkdir -p "$RUNTIME" "$VALIDATION"

state_json="$RUNTIME/dashboard-teardown-state.json"
expected_tsv="$RUNTIME/dashboard-saved-searches.tsv"
inventory_json="$RUNTIME/dashboard-saved-search-inventory.json"
delete_log="$RUNTIME/dashboard-saved-search-delete.log"
terraform -chdir="$TF_DIR" show -json terraform.tfstate > "$state_json"

resource_filter='.values.root_module.resources[]? | select(.address == "oci_management_dashboard_management_dashboards_import.wazuh[0]")'
dashboard_count="$(jq "[$resource_filter] | length" "$state_json")"
if [[ "$dashboard_count" -eq 0 ]]; then
  echo "dashboard_content_cleanup=skipped reason=not_in_state"
  exit 0
fi

normalize_import_details='if type == "string" then fromjson else . end'
import_details="$(jq -c "$resource_filter | .values.import_details | $normalize_import_details" "$state_json")"
compartment_id="$(jq -r --arg project "$project" '
  .dashboards[0]
  | select(.freeformTags.project == $project)
  | .compartmentId
' <<< "$import_details")"
[[ -n "$compartment_id" ]] || {
  echo "dashboard_content_cleanup=blocked reason=ownership_mismatch" >&2
  exit 6
}

jq -r --arg project "$project" '
  .dashboards[0]
  | select(.freeformTags.project == $project)
  | .savedSearches[]
  | select(.freeformTags.project == $project)
  | [.id, .displayName]
  | @tsv
' <<< "$import_details" > "$expected_tsv"
expected_count="$(wc -l < "$expected_tsv" | tr -d ' ')"
[[ "$expected_count" -gt 0 ]] || {
  echo "dashboard_content_cleanup=blocked reason=no_owned_saved_searches" >&2
  exit 6
}

oci --profile "$profile" management-dashboard saved-search list \
  --compartment-id "$compartment_id" \
  --all > "$inventory_json"

deleted_count=0
missing_count=0
: > "$delete_log"
while IFS=$'\t' read -r search_id expected_name; do
  match_count="$(jq --arg id "$search_id" '[.data.items[]? | select(.id == $id)] | length' "$inventory_json")"
  if [[ "$match_count" -eq 0 ]]; then
    missing_count=$((missing_count + 1))
    continue
  fi
  [[ "$match_count" -eq 1 ]] || {
    echo "dashboard_content_cleanup=blocked reason=ambiguous_saved_search" >&2
    exit 6
  }
  actual_project="$(jq -r --arg id "$search_id" '.data.items[] | select(.id == $id) | ."freeform-tags".project // ""' "$inventory_json")"
  actual_name="$(jq -r --arg id "$search_id" '.data.items[] | select(.id == $id) | ."display-name" // ""' "$inventory_json")"
  [[ "$actual_project" == "$project" && "$actual_name" == "$expected_name" ]] || {
    echo "dashboard_content_cleanup=blocked reason=saved_search_ownership_mismatch" >&2
    exit 6
  }
  oci --profile "$profile" management-dashboard saved-search delete \
    --management-saved-search-id "$search_id" \
    --force >> "$delete_log" 2>&1
  deleted_count=$((deleted_count + 1))
done < "$expected_tsv"

jq -n \
  --arg project "$project" \
  --argjson deleted "$deleted_count" \
  --argjson expected "$expected_count" \
  --argjson missing "$missing_count" \
  '{gate:"dashboard-content-cleanup",project_name:$project,expected_count:$expected,deleted_count:$deleted,already_absent_count:$missing,state:"green"}' \
  > "$VALIDATION/dashboard-content-cleanup.json"
echo "dashboard_content_cleanup=green deleted=$deleted_count already_absent=$missing_count"
