#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 -m m11.packaging --root "$ROOT_DIR" --output "$ROOT_DIR/artifacts/orm"
