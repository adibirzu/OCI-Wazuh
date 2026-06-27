"""Public-artifact secret and infrastructure-topology redaction."""

from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass(frozen=True)
class RedactionPattern:
    label: str
    regex: re.Pattern[str]
    replacement: str


PATTERNS = (
    RedactionPattern(
        "oci_ocid",
        re.compile(r"ocid1\.(?:tenancy|compartment|instance|cluster|networksecuritygroup|loadbalancer|subnet|vnic|bootvolume|loganalytics[a-z]*|user)\.oc1\.[A-Za-z0-9._-]*"),
        "<OCI_OCID>",
    ),
    RedactionPattern(
        "public_ip",
        re.compile(r"\b(?:130\.61|161\.153|144\.24|129\.153|141\.147|82\.77|109\.166)\.\d{1,3}\.\d{1,3}\b"),
        "<PUBLIC_IP>",
    ),
    RedactionPattern(
        "private_ip",
        re.compile(r"\b(?:10\.42\.\d{1,3}\.\d{1,3}|10\.0\.10\.\d{1,3})\b"),
        "<PRIVATE_IP>",
    ),
    RedactionPattern("ocir_namespace", re.compile(r"\b(?:fr4zqfimuxtr|axoxdievda5j|id9y6mi8tcky)\b"), "${OCIR_TENANCY}"),
    RedactionPattern("apm_domain", re.compile(r"\b(?:aaaadhp5ewo4eaaaaaaaaafs7q|axfo51x8x2ap)\b"), "<OBSERVABILITY_NAMESPACE>"),
    RedactionPattern(
        "fingerprint",
        re.compile(r"\b(?:[0-9a-fA-F]{2}:){15}[0-9a-fA-F]{2}\b"),
        "<OCI_KEY_FINGERPRINT>",
    ),
    RedactionPattern(
        "personal_path",
        re.compile(r"/(?:Users|home)/[^/\s]*@[^/\s]+(?:/[^\s]*)?"),
        "<PERSONAL_PATH>",
    ),
)

RUNTIME_TOPOLOGY_PATTERNS = (
    RedactionPattern("oci_ocid", re.compile(r"\bocid1\.[A-Za-z0-9._-]+"), "<OCI_OCID>"),
    RedactionPattern("ip_address", re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b"), "<REDACTED_IP>"),
)


def redact_text(value: str) -> str:
    redacted = value
    for pattern in PATTERNS:
        redacted = pattern.regex.sub(pattern.replacement, redacted)
    return redacted


def find_sensitive_values(value: str) -> list[str]:
    return [pattern.label for pattern in PATTERNS if pattern.regex.search(value)]


def find_runtime_topology(value: str) -> list[str]:
    """Return generic topology classes; callers must never echo matching values."""
    return [pattern.label for pattern in RUNTIME_TOPOLOGY_PATTERNS if pattern.regex.search(value)]
