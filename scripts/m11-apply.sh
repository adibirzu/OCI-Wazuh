#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/runtime
terraform -chdir=terraform plan -input=false -out="$(pwd)/artifacts/runtime/m11-apply.tfplan"
terraform -chdir=terraform apply -input=false -auto-approve "$(pwd)/artifacts/runtime/m11-apply.tfplan"
terraform -chdir=terraform output -json > artifacts/runtime/terraform-output.json
