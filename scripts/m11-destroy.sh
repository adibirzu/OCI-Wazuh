#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/runtime
if ! AUTO_APPROVE=true make down > artifacts/runtime/m11-destroy.log 2>&1; then
  echo "terraform_destroy=failed"
  exit 1
fi
echo "terraform_destroy=green"
