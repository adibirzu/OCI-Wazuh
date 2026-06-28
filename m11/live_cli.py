"""Operator entrypoint configuration for the unified M11 live workflow."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path
from typing import Mapping, Sequence

from m11.command_backend import CommandBackend, CommandSet
from m11.live_workflow import LiveWorkflow
from m11.provider_compat import provider_environment


def build_default_commands(project_name: str) -> CommandSet:
    query = (
        "query all resources where "
        f"(freeformTags.key = 'project' && freeformTags.value = '{project_name}')"
    )
    return CommandSet(
        preflight=(("terraform", "-chdir=terraform", "validate"),),
        apply=(("bash", "scripts/m11-apply.sh"),),
        validate=(("bash", "scripts/m11-validate.sh"),),
        cleanup=(("bash", "scripts/m11-cleanup.sh"),),
        destroy=(("bash", "scripts/m11-destroy.sh"),),
        residual=("oci", "search", "resource", "structured-search", "--query-text", query),
    )


def runner_environment(base: Mapping[str, str], *, mode: str, profile: str) -> dict[str, str]:
    return {**base, **provider_environment(mode, profile)}


def _runner(environment: Mapping[str, str]):
    def run(command: tuple[str, ...]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            env=dict(environment),
        )

    return run


def _discover(
    snapshot: Path,
    *,
    mode: str,
    profile: str,
    project_name: str,
    environment: Mapping[str, str],
) -> None:
    command = [
        sys.executable,
        "scripts/m11-discover.py",
        "--mode",
        mode,
        "--project-name",
        project_name,
        "--output",
        str(snapshot),
    ]
    if profile and mode == "local":
        command.extend(("--profile", profile))
    result = subprocess.run(command, check=False, env=dict(environment))
    if result.returncode != 0:
        raise RuntimeError("M11 discovery failed")


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("local", "orm"), default="local")
    parser.add_argument("--profile", default="")
    parser.add_argument("--project-name", default="oci-wazuh-demo")
    parser.add_argument("--snapshot", type=Path, default=Path("artifacts/runtime/reconciliation-snapshot.json"))
    parser.add_argument("--artifacts", type=Path, default=Path("artifacts/validation"))
    parser.add_argument("--run-id")
    parser.add_argument("--stop-after", choices=("preflight", "reconcile", "apply", "validate", "teardown"))
    parser.add_argument("--skip-discovery", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args(argv)

    environment = runner_environment(os.environ, mode=args.mode, profile=args.profile)
    environment["PROJECT_NAME"] = args.project_name
    def prepare(run_id: str) -> None:
        discovery_environment = {**environment, "M11_RUN_ID": run_id}
        _discover(
            args.snapshot,
            mode=args.mode,
            profile=args.profile,
            project_name=args.project_name,
            environment=discovery_environment,
        )

    backend = CommandBackend(
        args.snapshot,
        build_default_commands(args.project_name),
        run=_runner(environment),
        prepare=None if args.skip_discovery else prepare,
        diagnostic_path=Path("artifacts/runtime/m11-command-backend.log"),
    )
    summary = LiveWorkflow(args.artifacts, backend).run(
        mode=args.mode,
        run_id=args.run_id,
        stop_after=args.stop_after,
    )
    print(
        f"m11_run={summary.run_id} state={summary.state} "
        f"completed={','.join(summary.completed_stages)}"
    )
    return 0 if summary.state in {"green", "stopped"} else 1
