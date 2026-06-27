"""Validation artifact lifecycle helpers."""

from __future__ import annotations

import json
import shutil
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping


VALID_STATES = frozenset({"green", "failed", "skipped"})


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _clear_directory(directory: Path) -> None:
    if not directory.exists():
        return
    for child in directory.iterdir():
        if child.is_dir() and not child.is_symlink():
            shutil.rmtree(child)
        else:
            child.unlink()


def _write_json(path: Path, payload: Mapping[str, Any]) -> Path:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def begin_run(directory: Path, mode: str, run_id: str | None = None) -> dict[str, str]:
    """Clear stale evidence and initialize a uniquely identified validation run."""
    directory = Path(directory)
    _clear_directory(directory)
    directory.mkdir(parents=True, exist_ok=True)
    context = {
        "mode": mode,
        "run_id": run_id or str(uuid.uuid4()),
        "state": "green",
        "timestamp": utc_timestamp(),
    }
    _write_json(directory / "_run.json", context)
    return context


def write_gate(
    directory: Path,
    context: Mapping[str, str],
    gate: str,
    state: str,
    details: Mapping[str, Any],
) -> Path:
    """Write one self-describing gate artifact for the current run."""
    if state not in VALID_STATES:
        raise ValueError("state must be green, failed, or skipped")
    payload: dict[str, Any] = {
        "gate": gate,
        "mode": context["mode"],
        "run_id": context["run_id"],
        "state": state,
        "timestamp": context["timestamp"],
        **details,
    }
    return _write_json(Path(directory) / f"{gate}.json", payload)
