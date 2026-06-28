"""Subprocess helpers that prevent child output from reaching operator logs."""

from __future__ import annotations

import subprocess
import re
from collections.abc import Callable, Sequence


Runner = Callable[..., subprocess.CompletedProcess[str]]
DiagnosticClassifier = Callable[[str], str]


_VARIABLE_DECLARATION = re.compile(r'variable\s+"([a-z][a-z0-9_]*)"')


def classify_terraform_error(output: str) -> str:
    """Classify Terraform output without returning any untrusted text."""
    if "Invalid value for variable" in output:
        match = _VARIABLE_DECLARATION.search(output)
        if match:
            return f"invalid_variable:{match.group(1)}"
        return "invalid_variable"
    return "unclassified"


def run_quiet(
    command: Sequence[str],
    label: str,
    *,
    runner: Runner = subprocess.run,
    diagnostic_classifier: DiagnosticClassifier | None = None,
) -> subprocess.CompletedProcess[str]:
    """Run a command with captured output and raise only a fixed stage error."""
    result = runner(list(command), check=False, capture_output=True, text=True)
    if result.returncode != 0:
        diagnostic = ""
        if diagnostic_classifier is not None:
            classified = diagnostic_classifier(f"{result.stdout}\n{result.stderr}")
            diagnostic = f" [{classified}]"
        raise RuntimeError(f"{label} failed{diagnostic}")
    return result
