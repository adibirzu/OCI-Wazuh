"""Subprocess-backed implementation of the live workflow boundary."""

from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from m11.live_workflow import PreflightSnapshot
from m11.reconciliation import ConnectorCapacity, ExpectedResource, ObservedResource


Command = tuple[str, ...]
Runner = Callable[[Command], subprocess.CompletedProcess[str]]


@dataclass(frozen=True)
class CommandSet:
    preflight: tuple[Command, ...] = ()
    apply: tuple[Command, ...] = (("terraform", "-chdir=terraform", "apply", "-input=false", "-auto-approve"),)
    validate: tuple[Command, ...] = ()
    cleanup: tuple[Command, ...] = ()
    destroy: tuple[Command, ...] = ()
    residual: Command = ()


def _default_run(command: Command) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, check=False, capture_output=True, text=True)


class CommandBackend:
    def __init__(
        self,
        snapshot_path: Path,
        commands: CommandSet,
        *,
        run: Runner = _default_run,
    ) -> None:
        self._snapshot_path = Path(snapshot_path)
        self._commands = commands
        self._run = run

    def _execute(self, command: Command) -> subprocess.CompletedProcess[str]:
        if not command:
            raise RuntimeError("command is not configured")
        result = self._run(command)
        if result.returncode != 0:
            raise RuntimeError(f"command failed: {command[0]}")
        return result

    def _all_green(self, commands: tuple[Command, ...]) -> bool:
        if not commands:
            return True
        for command in commands:
            try:
                self._execute(command)
            except RuntimeError:
                return False
        return True

    def _load_snapshot(self) -> PreflightSnapshot:
        try:
            payload = json.loads(self._snapshot_path.read_text(encoding="utf-8"))
            project_name = payload["project_name"]
            expected = tuple(ExpectedResource(**item) for item in payload["expected"])
            observed = tuple(ObservedResource(**item) for item in payload["observed"])
            capacity = ConnectorCapacity(**payload["connector_capacity"])
        except (KeyError, TypeError, ValueError, json.JSONDecodeError, OSError) as exc:
            raise ValueError("invalid reconciliation snapshot") from exc
        if not isinstance(project_name, str) or not project_name:
            raise ValueError("invalid reconciliation snapshot")
        return PreflightSnapshot(project_name, expected, observed, capacity)

    def preflight(self, run_id: str) -> PreflightSnapshot:
        del run_id
        for command in self._commands.preflight:
            self._execute(command)
        return self._load_snapshot()

    def import_resource(self, address: str, resource_id: str) -> None:
        self._execute(("terraform", "-chdir=terraform", "import", address, resource_id))

    def apply(self, run_id: str) -> None:
        del run_id
        for command in self._commands.apply:
            self._execute(command)

    def validate(self, run_id: str) -> bool:
        del run_id
        return self._all_green(self._commands.validate)

    def cleanup_reused_hosts(self, run_id: str) -> bool:
        del run_id
        return self._all_green(self._commands.cleanup)

    def destroy(self, run_id: str) -> None:
        del run_id
        for command in self._commands.destroy:
            self._execute(command)

    def residual_resource_ids(self) -> list[str]:
        try:
            result = self._execute(self._commands.residual)
            payload = json.loads(result.stdout)
            items = payload["data"]["items"]
            identifiers = [item["identifier"] for item in items]
        except (KeyError, TypeError, json.JSONDecodeError) as exc:
            raise ValueError("invalid residual search output") from exc
        if not all(isinstance(identifier, str) for identifier in identifiers):
            raise ValueError("invalid residual search output")
        return identifiers
