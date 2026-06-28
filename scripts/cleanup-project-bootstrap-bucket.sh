#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"
RUNTIME="$ROOT_DIR/artifacts/runtime"
VALIDATION="$ROOT_DIR/artifacts/validation"
project="${1:?project name required}"
profile="${2:-DEFAULT}"
mkdir -p "$RUNTIME" "$VALIDATION"

state_json="$RUNTIME/bootstrap-bucket-teardown-state.json"
versions_json="$RUNTIME/bootstrap-bucket-object-versions.json"
delete_log="$RUNTIME/bootstrap-bucket-object-delete.log"
terraform -chdir="$TF_DIR" show -json terraform.tfstate > "$state_json"
resource_filter='.values.root_module.resources[]? | select(.address == "oci_objectstorage_bucket.bootstrap")'
bucket_count="$(jq "[$resource_filter] | length" "$state_json")"
if [[ "$bucket_count" -eq 0 ]]; then
  echo "bootstrap_bucket_cleanup=skipped reason=not_in_state"
  exit 0
fi

owned="$(jq -r --arg project "$project" '
  .values.root_module.resources[]?
  | select(.address == "oci_objectstorage_bucket.bootstrap")
  | .values.freeform_tags.project == $project and .values.freeform_tags.role == "bootstrap"
' "$state_json")"
[[ "$owned" == "true" ]] || {
  echo "bootstrap_bucket_cleanup=blocked reason=ownership_mismatch" >&2
  exit 6
}

bucket_name="$(jq -r "$resource_filter | .values.name" "$state_json")"
namespace="$(jq -r "$resource_filter | .values.namespace" "$state_json")"
oci --profile "$profile" os object list-object-versions \
  --namespace "$namespace" \
  --bucket-name "$bucket_name" \
  --all > "$versions_json"

unexpected_count="$(jq '[.data[]? | select(((.name | startswith("bootstrap/")) or (.name | startswith("status/")) or (.name | startswith("windows/"))) | not)] | length' "$versions_json")"
[[ "$unexpected_count" -eq 0 ]] || {
  echo "bootstrap_bucket_cleanup=blocked reason=unexpected_object_prefix" >&2
  exit 6
}

version_count="$(jq '.data | length' "$versions_json")"
: > "$delete_log"
while IFS=$'\t' read -r object_name version_id; do
  [[ -n "$object_name" ]] || continue
  command=(
    oci --profile "$profile" os object delete
    --namespace "$namespace"
    --bucket-name "$bucket_name"
    --object-name "$object_name"
    --force
  )
  if [[ -n "$version_id" && "$version_id" != "null" ]]; then
    command+=(--version-id "$version_id")
  fi
  "${command[@]}" >> "$delete_log" 2>&1
done < <(jq -r '.data[]? | [.name, (."version-id" // "")] | @tsv' "$versions_json")

jq -n \
  --arg project "$project" \
  --argjson deleted "$version_count" \
  '{gate:"bootstrap-bucket-cleanup",project_name:$project,deleted_object_versions:$deleted,state:"green"}' \
  > "$VALIDATION/bootstrap-bucket-cleanup.json"
echo "bootstrap_bucket_cleanup=green deleted_versions=$version_count"
