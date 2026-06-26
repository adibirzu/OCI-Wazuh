#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/artifacts/orm"
OUT_ZIP="${OUT_DIR}/oci-wazuh-orm-stack.zip"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/oci-wazuh-orm.XXXXXX")"

cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

mkdir -p "${OUT_DIR}"

cp "${ROOT_DIR}"/terraform/*.tf "${WORK_DIR}/"
cp -R "${ROOT_DIR}/terraform/modules" "${WORK_DIR}/modules"
cp -R "${ROOT_DIR}/ansible" "${WORK_DIR}/ansible"
cp -R "${ROOT_DIR}/wazuh" "${WORK_DIR}/wazuh"
cp -R "${ROOT_DIR}/dashboards" "${WORK_DIR}/dashboards"
cp -R "${ROOT_DIR}/scripts" "${WORK_DIR}/scripts"
cp "${ROOT_DIR}/docs/ORM_RESOURCE_MANAGER_DEPLOYMENT.md" "${WORK_DIR}/README.md"

find "${WORK_DIR}" -name ".DS_Store" -delete
find "${WORK_DIR}" -name "terraform.tfvars" -delete
find "${WORK_DIR}" -name "terraform.tfstate*" -delete
find "${WORK_DIR}" -name "__pycache__" -type d -prune -exec rm -rf {} +
find "${WORK_DIR}" -name "*.pyc" -delete

rm -f "${OUT_ZIP}"
(
  cd "${WORK_DIR}"
  zip -qr "${OUT_ZIP}" .
)

echo "orm_stack_zip=${OUT_ZIP}"
