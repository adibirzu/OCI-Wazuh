"""Subprocess helpers that prevent child output from reaching operator logs."""

from __future__ import annotations

import subprocess
import re
import os
from collections.abc import Callable, Sequence
from pathlib import Path


Runner = Callable[..., subprocess.CompletedProcess[str]]
DiagnosticClassifier = Callable[[str], str]


_VARIABLE_DECLARATION = re.compile(r'variable\s+"([a-z][a-z0-9_]*)"')
_ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*m")
_OCI_SERVICE_ERROR = re.compile(r"Error:\s+([45][0-9]{2})-[A-Za-z][A-Za-z0-9]*")
_TERRAFORM_SOURCE = re.compile(r"\bon ([a-z][a-z0-9_-]*\.tf) line ([1-9][0-9]*)\b")
_SAFE_TERRAFORM_DIAGNOSTICS = (
    ('The argument "namespace" is required', "missing_namespace"),
    ("availability_domain_index is outside", "availability_domain_unavailable"),
    ("selected availability domain is not available", "availability_domain_unavailable"),
    ("Compatible Oracle Linux 9 and Ubuntu 24.04", "linux_images_unavailable"),
    ("selected Linux shapes are unavailable", "linux_shapes_unavailable"),
    ("Log Analytics is enabled but no namespace is onboarded", "log_analytics_namespace_missing"),
    ("Set ssh_public_key", "ssh_public_key_missing"),
    ("Set tenancy_ocid and compartment_ocid", "identity_inputs_missing"),
)


def classify_terraform_error(output: str) -> str:
    """Classify Terraform output without returning any untrusted text."""
    normalized = _ANSI_ESCAPE.sub("", output)
    if "Invalid value for variable" in normalized:
        match = _VARIABLE_DECLARATION.search(normalized)
        if match:
            return f"invalid_variable:{match.group(1)}"
        return "invalid_variable"
    for phrase, classification in _SAFE_TERRAFORM_DIAGNOSTICS:
        if phrase in normalized:
            return classification
    service_error = _OCI_SERVICE_ERROR.search(normalized)
    if service_error:
        return f"oci_service_error:{service_error.group(1)}"
    source = _TERRAFORM_SOURCE.search(normalized)
    if source:
        return f"terraform_source:{source.group(1)}:{source.group(2)}"
    return "unclassified"


def run_quiet(
    command: Sequence[str],
    label: str,
    *,
    runner: Runner = subprocess.run,
    diagnostic_classifier: DiagnosticClassifier | None = None,
    diagnostic_path: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    """Run a command with captured output and raise only a fixed stage error."""
    result = runner(list(command), check=False, capture_output=True, text=True)
    if result.returncode != 0:
        if diagnostic_path is not None:
            diagnostic_path.parent.mkdir(parents=True, exist_ok=True)
            flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
            descriptor = os.open(diagnostic_path, flags, 0o600)
            with os.fdopen(descriptor, "w", encoding="utf-8") as diagnostics:
                diagnostics.write(f"{result.stdout}\n{result.stderr}\n")
        diagnostic = ""
        if diagnostic_classifier is not None:
            classified = diagnostic_classifier(f"{result.stdout}\n{result.stderr}")
            diagnostic = f" [{classified}]"
        raise RuntimeError(f"{label} failed{diagnostic}")
    return result
