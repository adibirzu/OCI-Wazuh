"""Local/ORM profile separation and evidence-backed provider overrides."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping


ALLOWED_OVERRIDES = frozenset(
    {
        "object_storage_namespace",
        "log_analytics_namespace",
        "availability_domain",
        "ol9_image_id",
        "ubuntu2404_image_id",
        "windows2022_image_id",
    }
)


@dataclass(frozen=True)
class OverrideEvidence:
    provider_values: Mapping[str, str | None]
    cli_values: Mapping[str, str | None]


def provider_environment(mode: str, profile: str) -> dict[str, str]:
    """Return profile variables only for an explicitly configured local run."""
    if mode not in {"local", "orm"}:
        raise ValueError("mode must be local or orm")
    if mode == "orm" or not profile:
        return {}
    return {"OCI_CONFIG_PROFILE": profile, "TF_VAR_oci_config_profile": profile}


def validate_overrides(
    overrides: Mapping[str, str],
    evidence: OverrideEvidence,
) -> dict[str, str]:
    """Accept only allowlisted values verified by same-run OCI CLI evidence."""
    validated: dict[str, str] = {}
    for name, value in overrides.items():
        if name not in ALLOWED_OVERRIDES:
            raise ValueError(f"unsupported provider override: {name}")
        if not value or evidence.cli_values.get(name) != value:
            raise ValueError(f"CLI preflight did not verify override: {name}")
        provider_value = evidence.provider_values.get(name)
        if provider_value not in {None, "", value}:
            raise ValueError(f"override conflicts with provider discovery: {name}")
        validated[name] = value
    return validated
