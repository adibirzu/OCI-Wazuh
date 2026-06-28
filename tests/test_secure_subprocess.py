import subprocess

import pytest

from m11.secure_subprocess import run_quiet


def test_run_quiet_captures_output_without_returning_it() -> None:
    calls: list[tuple[list[str], dict[str, object]]] = []

    def runner(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        calls.append((command, kwargs))
        return subprocess.CompletedProcess(command, 0, "sensitive topology", "")

    result = run_quiet(["terraform", "plan"], "Terraform plan", runner=runner)

    assert result.returncode == 0
    assert calls == [
        (
            ["terraform", "plan"],
            {"check": False, "capture_output": True, "text": True},
        )
    ]


def test_run_quiet_failure_never_exposes_subprocess_output() -> None:
    sensitive = "ocid1.example.internal-topology"

    def runner(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess(command, 1, sensitive, sensitive)

    with pytest.raises(RuntimeError, match=r"^Terraform plan failed$") as failure:
        run_quiet(["terraform", "plan"], "Terraform plan", runner=runner)

    assert sensitive not in str(failure.value)
