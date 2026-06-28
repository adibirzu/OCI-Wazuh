from pathlib import Path
import subprocess
import sys

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


def test_live_workflow_maps_provider_null_fallbacks_from_protected_secrets() -> None:
    workflow = (ROOT / ".github/workflows/live-m11.yml").read_text(encoding="utf-8")

    expected = {
        "TF_VAR_availability_domain": "OCI_AVAILABILITY_DOMAIN",
        "TF_VAR_ol9_image_id": "OCI_OL9_IMAGE_OCID",
        "TF_VAR_ubuntu2404_image_id": "OCI_UBUNTU2404_IMAGE_OCID",
        "TF_VAR_object_storage_namespace": "OCI_OBJECT_STORAGE_NAMESPACE",
        "TF_VAR_log_analytics_namespace": "OCI_LOG_ANALYTICS_NAMESPACE",
    }
    for variable, secret in expected.items():
        assert f"{variable}: ${{{{ secrets.{secret} }}}}" in workflow


def test_live_workflow_restricts_bastion_to_runner_and_tears_down_on_failure() -> None:
    workflow = (ROOT / ".github/workflows/live-m11.yml").read_text(encoding="utf-8")

    assert "TF_VAR_operator_cidr: ${{ secrets.OPERATOR_CIDR }}" not in workflow
    assert "name: Resolve protected runner CIDR" in workflow
    assert 'echo "::add-mask::$runner_ip"' in workflow
    assert 'TF_VAR_operator_cidr=$runner_ip/32' in workflow
    assert "name: Guarded failure teardown" in workflow
    assert "failure() && inputs.destroy_after_validation" in workflow
    assert "bash scripts/m11-cleanup.sh" in workflow
    assert "bash scripts/m11-destroy.sh" in workflow


def test_live_workflow_uploads_only_encrypted_runtime_diagnostics() -> None:
    workflow = (ROOT / ".github/workflows/live-m11.yml").read_text(encoding="utf-8")

    assert "M11_DIAGNOSTIC_ENCRYPTION_KEY" in workflow
    assert "openssl enc -aes-256-cbc -pbkdf2 -salt" in workflow
    assert 'artifacts/validation/$(basename "$source").enc' in workflow
    assert "path: artifacts/runtime/" not in workflow


def test_discovery_inventories_unowned_name_collisions_before_apply() -> None:
    discovery = (ROOT / "scripts/m11-discover.py").read_text(encoding="utf-8")

    assert 'query = "query all resources"' in discovery
    assert "freeformTags.key = 'project'" not in discovery
    assert '"--limit",' in discovery
    assert '"1000",' in discovery
    for label in (
        "Terraform plan rendering",
        "OCI resource search",
        "OCI Service Connector limit query",
    ):
        assert label in discovery
    assert "normalize_logging_logs" in discovery
    assert '"logging",' in discovery
    assert '"log",' in discovery
    assert '"list",' in discovery


def test_terraform_stage_output_is_kept_out_of_public_logs() -> None:
    discovery = (ROOT / "scripts/m11-discover.py").read_text(encoding="utf-8")
    assert "run_quiet(" in discovery

    expected_logs = {
        "m11-apply.sh": ("m11-plan.log", "m11-apply.log"),
        "m11-cleanup.sh": ("m11-cleanup.log",),
        "m11-destroy.sh": ("m11-destroy.log",),
    }
    for script, logs in expected_logs.items():
        content = (ROOT / "scripts" / script).read_text(encoding="utf-8")
        for log in logs:
            assert f"artifacts/runtime/{log}" in content
        assert "2>&1" in content


def test_destroy_path_purges_only_state_owned_log_analytics_and_retries() -> None:
    destroy = (ROOT / "scripts/down.sh").read_text(encoding="utf-8")
    purge = (ROOT / "scripts/purge-project-log-analytics.sh").read_text(encoding="utf-8")
    dashboards = (ROOT / "scripts/cleanup-project-dashboard-content.sh").read_text(encoding="utf-8")
    bucket = (ROOT / "scripts/cleanup-project-bootstrap-bucket.sh").read_text(encoding="utf-8")

    assert "purge-project-log-analytics.sh" in destroy
    assert "cleanup-project-dashboard-content.sh" in destroy
    assert "cleanup-project-bootstrap-bucket.sh" in destroy
    assert 'destroy_max_attempts="${DESTROY_MAX_ATTEMPTS:-12}"' in destroy
    assert 'destroy_retry_seconds="${DESTROY_RETRY_SECONDS:-60}"' in destroy
    assert 'for destroy_attempt in $(seq 1 "$destroy_max_attempts")' in destroy
    assert 'destroy-plan.log' in destroy
    assert 'destroy-apply.log' in destroy
    assert '> "$destroy_apply_log" 2>&1' in destroy
    assert "guard-destroy-plan.py" in destroy
    assert 'freeform_tags.project == \\$project' in purge
    assert 'logGroupId:\\"$group_id\\"' in purge
    assert "get-storage-work-request" in purge
    assert "oci_management_dashboard_management_dashboards_import.wazuh[0]" in dashboards
    assert 'if type == "string" then fromjson else . end' in dashboards
    assert '.freeformTags.project == $project' in dashboards
    assert "management-dashboard saved-search delete" in dashboards
    assert "oci_objectstorage_bucket.bootstrap" in bucket
    assert '.freeform_tags.project == $project' in bucket
    assert 'startswith("bootstrap/")' in bucket
    assert 'startswith("status/")' in bucket
    assert 'startswith("windows/")' in bucket
    assert "os object delete" in bucket
    confirmation = destroy.index('if [[ "${AUTO_APPROVE:-false}"')
    cleanup = destroy.index('bash "$ROOT_DIR/scripts/cleanup-project-dashboard-content.sh"')
    purge_call = destroy.index('bash "$ROOT_DIR/scripts/purge-project-log-analytics.sh"')
    assert confirmation < cleanup < purge_call


def test_e2e_fails_fast_with_private_wazuh_bootstrap_diagnostics() -> None:
    e2e = (ROOT / "scripts/e2e.sh").read_text(encoding="utf-8")

    assert "cloud-init status --wait" in e2e
    assert "wazuh_bootstrap=failed" in e2e
    assert "/var/log/oci-wazuh-demo/wazuh-install.log" in e2e
    assert "grep -E -i 'error|failed|could not|unsupported|unable'" in e2e


def test_published_python_entrypoints_resolve_project_modules() -> None:
    for script in ("m11-live.py", "m11-discover.py"):
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / script), "--help"],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, result.stderr
