from pathlib import Path

from m11.live_cli import build_default_commands, runner_environment


ROOT = Path(__file__).resolve().parents[1]


def test_default_command_sequence_uses_fixed_project_scripts() -> None:
    commands = build_default_commands("oci-wazuh-demo")

    assert commands.preflight == (("terraform", "-chdir=terraform", "validate"),)
    assert commands.apply == (("bash", "scripts/m11-apply.sh"),)
    assert commands.validate == (("bash", "scripts/m11-validate.sh"),)
    assert commands.cleanup == (("bash", "scripts/m11-cleanup.sh"),)
    assert commands.destroy == (("bash", "scripts/m11-destroy.sh"),)
    assert commands.residual[:3] == ("oci", "search", "resource")
    assert "oci-wazuh-demo" in commands.residual[-1]


def test_runner_environment_keeps_orm_profile_free() -> None:
    base = {"PATH": "/usr/bin"}

    assert runner_environment(base, mode="orm", profile="cap") == base
    assert runner_environment(base, mode="local", profile="")["PATH"] == "/usr/bin"
    local = runner_environment(base, mode="local", profile="cap")
    assert local["OCI_CONFIG_PROFILE"] == "cap"
    assert local["TF_VAR_oci_config_profile"] == "cap"


def test_live_workflow_uses_one_controller_and_required_stage_scripts() -> None:
    workflow = (ROOT / ".github/workflows/live-m11.yml").read_text(encoding="utf-8")

    assert "python3 scripts/m11-live.py" in workflow
    assert "name: Terraform apply" not in workflow
    for script in (
        "m11-live.py",
        "m11-discover.py",
        "m11-apply.sh",
        "m11-validate.sh",
        "m11-cleanup.sh",
        "m11-destroy.sh",
    ):
        assert (ROOT / "scripts" / script).is_file()
