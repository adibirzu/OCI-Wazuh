#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/runtime
if ! terraform -chdir=terraform plan -input=false -out="$(pwd)/artifacts/runtime/m11-apply.tfplan" > artifacts/runtime/m11-plan.log 2>&1; then
  echo "terraform_plan=failed"
  exit 1
fi
if ! terraform -chdir=terraform apply -input=false -auto-approve "$(pwd)/artifacts/runtime/m11-apply.tfplan" > artifacts/runtime/m11-apply.log 2>&1; then
  echo "terraform_apply=failed"
  exit 1
fi
if ! terraform -chdir=terraform output -json > artifacts/runtime/terraform-output.json 2> artifacts/runtime/m11-output.log; then
  echo "terraform_output=failed"
  exit 1
fi
echo "terraform_apply=green"
