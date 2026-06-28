#!/usr/bin/env python3
"""Run the unified M11 deployment lifecycle."""

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from m11.live_cli import main


if __name__ == "__main__":
    raise SystemExit(main())
