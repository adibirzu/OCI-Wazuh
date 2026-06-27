from datetime import datetime, timezone

from m11.validation import DetectionEvidence, validate_current_run_detections, validate_private_topology


def test_real_detections_must_match_run_and_be_newer_than_run_start() -> None:
    started = datetime(2026, 6, 28, 8, 0, tzinfo=timezone.utc)
    evidence = [
        DetectionEvidence("100000", "run-1", datetime(2026, 6, 28, 8, 1, tzinfo=timezone.utc), synthetic=False),
        DetectionEvidence("100100", "run-1", datetime(2026, 6, 28, 8, 2, tzinfo=timezone.utc), synthetic=False),
    ]

    result = validate_current_run_detections(evidence, "run-1", started)

    assert result == {"100000": "green", "100100": "green"}


def test_stale_synthetic_or_other_run_detections_cannot_satisfy_gate() -> None:
    started = datetime(2026, 6, 28, 8, 0, tzinfo=timezone.utc)
    evidence = [
        DetectionEvidence("100000", "run-1", datetime(2026, 6, 28, 7, 59, tzinfo=timezone.utc), synthetic=False),
        DetectionEvidence("100000", "run-1", datetime(2026, 6, 28, 8, 1, tzinfo=timezone.utc), synthetic=True),
        DetectionEvidence("100100", "run-old", datetime(2026, 6, 28, 8, 2, tzinfo=timezone.utc), synthetic=False),
    ]

    assert validate_current_run_detections(evidence, "run-1", started) == {
        "100000": "failed",
        "100100": "failed",
    }


def test_private_topology_allows_only_bastion_public_address() -> None:
    assert validate_private_topology(
        {"bastion": "public", "wazuh": "private", "ol9": "private", "ubuntu": "private"}
    ) == []
    assert validate_private_topology(
        {"bastion": "public", "wazuh": "public", "ol9": "private"}
    ) == ["wazuh"]
