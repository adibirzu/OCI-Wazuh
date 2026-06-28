"""Subprocess helpers that prevent child output from reaching operator logs."""

from __future__ import annotations

import subprocess
from collections.abc import Callable, Sequence


Runner = Callable[..., subprocess.CompletedProcess[str]]


def run_quiet(
    command: Sequence[str],
    label: str,
    *,
    runner: Runner = subprocess.run,
) -> subprocess.CompletedProcess[str]:
    """Run a command with captured output and raise only a fixed stage error."""
    result = runner(list(command), check=False, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"{label} failed")
    return result
