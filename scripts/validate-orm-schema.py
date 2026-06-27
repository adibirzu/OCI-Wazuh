#!/usr/bin/env python3
import sys
from pathlib import Path


root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root))

from m11.schema_contract import validate_schema_parity  # noqa: E402
errors = validate_schema_parity(root / "terraform/schema.yaml", root / "terraform/variables.tf")
for error in errors:
    print(error)
print(f"orm_schema={'green' if not errors else 'failed'}")
raise SystemExit(1 if errors else 0)
