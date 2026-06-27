import json
import subprocess
from pathlib import Path

import pytest

from m11.command_backend import CommandBackend, CommandSet


def write_snapshot(path: Path) -> None:
    path.write_text(
        json.dumps(
            {
                "project_name": "oci-wazuh-demo",
                "connector_capacity": {"limit": 2, "active_count": 1},
                "expected": [
                    {
                        "address": "oci_identity_dynamic_group.demo",
                        "resource_type": "oci_identity_dynamic_group",
                        "name": "oci-wazuh-demo-dg",
                        "tags": {"project": "oci-wazuh-demo"},
                        "configuration": {"fingerprint": "expected"},
                    }
                ],
                "observed": [],
            }
        ),
        encoding="utf-8",
    )


def test_backend_loads_snapshot_and_executes_argument_vectors(tmp_path: Path) -> None:
    snapshot = tmp_path / "snapshot.json"
    write_snapshot(snapshot)
    calls: list[tuple[str, ...]] = []

    def run(command: tuple[str, ...]) -> subprocess.CompletedProcess[str]:
        calls.append(command)
        stdout = '{"data":{"items":[]}}' if command == ("residual",) else ""
        return subprocess.CompletedProcess(command, 0, stdout=stdout, stderr="")

    backend = CommandBackend(
        snapshot,
        CommandSet(
            preflight=(("preflight",),),
            apply=(("apply",),),
            validate=(("validate-one",), ("validate-two",)),
            cleanup=(("cleanup",),),
            destroy=(("destroy",),),
            residual=("residual",),
        ),
        run=run,
    )

    loaded = backend.preflight("run-1")
    backend.import_resource("oci_identity_dynamic_group.demo", "synthetic-id")
    backend.apply("run-1")

    assert loaded.project_name == "oci-wazuh-demo"
    assert backend.validate("run-1") is True
    assert backend.cleanup_reused_hosts("run-1") is True
    backend.destroy("run-1")
    assert backend.residual_resource_ids() == []
    assert ("terraform", "-chdir=terraform", "import", "oci_identity_dynamic_group.demo", "synthetic-id") in calls


def test_backend_fails_closed_on_command_error_or_invalid_snapshot(tmp_path: Path) -> None:
    snapshot = tmp_path / "snapshot.json"
    write_snapshot(snapshot)

    def fail(command: tuple[str, ...]) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess(command, 1, stdout="", stderr="sensitive detail")

    backend = CommandBackend(snapshot, CommandSet(validate=(("validate",),)), run=fail)

    assert backend.validate("run-1") is False
    with pytest.raises(RuntimeError, match="command failed"):
        backend.apply("run-1")

    snapshot.write_text('{"project_name":"wrong"}', encoding="utf-8")
    with pytest.raises(ValueError, match="snapshot"):
        backend.preflight("run-1")


def test_residual_parser_returns_ids_internally_but_rejects_malformed_output(tmp_path: Path) -> None:
    snapshot = tmp_path / "snapshot.json"
    write_snapshot(snapshot)

    def residual(command: tuple[str, ...]) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess(
            command,
            0,
            stdout=json.dumps({"data": {"items": [{"identifier": "private-id"}]}}),
            stderr="",
        )

    backend = CommandBackend(snapshot, CommandSet(residual=("residual",)), run=residual)
    assert backend.residual_resource_ids() == ["private-id"]

    malformed = CommandBackend(
        snapshot,
        CommandSet(residual=("residual",)),
        run=lambda command: subprocess.CompletedProcess(command, 0, stdout="not-json", stderr=""),
    )
    with pytest.raises(ValueError, match="residual search output"):
        malformed.residual_resource_ids()
