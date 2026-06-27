"""Current-run telemetry and network-posture decisions."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Mapping, Sequence


@dataclass(frozen=True)
class DetectionEvidence:
    rule_id: str
    run_id: str
    timestamp: datetime
    synthetic: bool


def validate_current_run_detections(
    evidence: Sequence[DetectionEvidence],
    run_id: str,
    run_started: datetime,
) -> dict[str, str]:
    required = ("100000", "100100")
    return {
        rule_id: "green"
        if any(
            item.rule_id == rule_id
            and item.run_id == run_id
            and item.timestamp > run_started
            and not item.synthetic
            for item in evidence
        )
        else "failed"
        for rule_id in required
    }


def validate_private_topology(host_visibility: Mapping[str, str]) -> list[str]:
    """Return workload names that violate the bastion-only public boundary."""
    return sorted(
        host
        for host, visibility in host_visibility.items()
        if host != "bastion" and visibility != "private"
    )
