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
dashboard_inventory_json="$RUNTIME/dashboard-inventory.json"
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
dashboard_id="$(jq -r --arg project "$project" '.dashboards[0] | select(.freeformTags.project == $project) | .dashboardId' <<< "$import_details")"
dashboard_name="$(jq -r --arg project "$project" '.dashboards[0] | select(.freeformTags.project == $project) | .displayName' <<< "$import_details")"
[[ -n "$dashboard_id" && "$dashboard_name" == "${project}-correlation" ]] || {
  echo "dashboard_content_cleanup=blocked reason=dashboard_ownership_mismatch" >&2
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

visible_search_count=0
live_dashboard_count=0
for inventory_attempt in $(seq 1 12); do
  oci --profile "$profile" management-dashboard saved-search list \
    --compartment-id "$compartment_id" --all > "$inventory_json"
  oci --profile "$profile" management-dashboard dashboard list \
    --compartment-id "$compartment_id" --all > "$dashboard_inventory_json"
  visible_search_count="$(jq --rawfile expected "$expected_tsv" '
    ($expected | split("\n") | map(select(length > 0) | split("\t")[0])) as $ids
    | [.data.items[]? | select(.id as $id | $ids | index($id))] | length
  ' "$inventory_json")"
  live_dashboard_count="$(jq --arg id "$dashboard_id" '[.data.items[]? | select(.id == $id)] | length' "$dashboard_inventory_json")"
  if [[ "$visible_search_count" -eq "$expected_count" && "$live_dashboard_count" -eq 1 ]]; then
    break
  fi
  echo "dashboard_content_cleanup=waiting_for_inventory attempt=$inventory_attempt/12" >&2
  sleep 10
done
if [[ "$live_dashboard_count" -gt 0 && "$visible_search_count" -ne "$expected_count" ]]; then
  echo "dashboard_content_cleanup=failed reason=incomplete_eventual_inventory" >&2
  exit 7
fi

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

if [[ "$live_dashboard_count" -gt 0 ]]; then
  [[ "$live_dashboard_count" -eq 1 ]] || {
    echo "dashboard_content_cleanup=blocked reason=ambiguous_dashboard" >&2
    exit 6
  }
  actual_dashboard_project="$(jq -r --arg id "$dashboard_id" '.data.items[] | select(.id == $id) | ."freeform-tags".project // ""' "$dashboard_inventory_json")"
  actual_dashboard_name="$(jq -r --arg id "$dashboard_id" '.data.items[] | select(.id == $id) | ."display-name" // ""' "$dashboard_inventory_json")"
  [[ "$actual_dashboard_project" == "$project" && "$actual_dashboard_name" == "$dashboard_name" ]] || {
    echo "dashboard_content_cleanup=blocked reason=dashboard_ownership_mismatch" >&2
    exit 6
  }
  oci --profile "$profile" management-dashboard dashboard delete \
    --management-dashboard-id "$dashboard_id" --force >> "$delete_log" 2>&1
fi

remaining_count=1
for absence_attempt in $(seq 1 12); do
  oci --profile "$profile" management-dashboard saved-search list \
    --compartment-id "$compartment_id" --all > "$inventory_json"
  oci --profile "$profile" management-dashboard dashboard list \
    --compartment-id "$compartment_id" --all > "$dashboard_inventory_json"
  remaining_searches="$(jq --rawfile expected "$expected_tsv" '
    ($expected | split("\n") | map(select(length > 0) | split("\t")[0])) as $ids
    | [.data.items[]? | select(.id as $id | $ids | index($id))] | length
  ' "$inventory_json")"
  remaining_dashboards="$(jq --arg id "$dashboard_id" '[.data.items[]? | select(.id == $id)] | length' "$dashboard_inventory_json")"
  remaining_count=$((remaining_searches + remaining_dashboards))
  [[ "$remaining_count" -eq 0 ]] && break
  echo "dashboard_content_cleanup=waiting_for_absence attempt=$absence_attempt/12" >&2
  sleep 10
done
[[ "$remaining_count" -eq 0 ]] || {
  echo "dashboard_content_cleanup=failed reason=residual_content" >&2
  exit 7
}

jq -n \
  --arg project "$project" \
  --argjson deleted "$deleted_count" \
  --argjson expected "$expected_count" \
  --argjson missing "$missing_count" \
  '{gate:"dashboard-content-cleanup",project_name:$project,expected_count:$expected,deleted_count:$deleted,already_absent_count:$missing,state:"green"}' \
  > "$VALIDATION/dashboard-content-cleanup.json"
echo "dashboard_content_cleanup=green deleted=$deleted_count already_absent=$missing_count"
