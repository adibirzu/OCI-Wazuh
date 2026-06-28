import subprocess
import stat

import pytest

from m11.secure_subprocess import classify_terraform_error, run_quiet


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


def test_terraform_error_classifier_reports_only_validated_variable_name() -> None:
    output = '''
Error: Invalid value for variable
  on variables.tf line 342:
 342: variable "goad_instance_ocids" {
var.goad_instance_ocids is "ocid1.example.sensitive"
'''

    assert classify_terraform_error(output) == "invalid_variable:goad_instance_ocids"


def test_terraform_error_classifier_does_not_echo_unknown_output() -> None:
    output = "Error: provider exposed ocid1.example.sensitive and internal namespace"

    assert classify_terraform_error(output) == "unclassified"


@pytest.mark.parametrize(
    ("output", "expected"),
    (
        ('Error: Missing required argument\nThe argument "namespace" is required', "missing_namespace"),
        (
            "Error: Resource precondition failed\n"
            "The selected availability domain is not available in this tenancy and region.",
            "availability_domain_unavailable",
        ),
        (
            "Error: Resource precondition failed\n"
            "Compatible Oracle Linux 9 and Ubuntu 24.04 platform images were not found",
            "linux_images_unavailable",
        ),
        (
            "Error: Resource precondition failed\n"
            "Log Analytics is enabled but no namespace is onboarded",
            "log_analytics_namespace_missing",
        ),
        ("Error: 404-NotAuthorizedOrNotFound", "oci_service_error:404"),
    ),
)
def test_terraform_error_classifier_uses_fixed_safe_categories(
    output: str,
    expected: str,
) -> None:
    assert classify_terraform_error(output) == expected


def test_terraform_error_classifier_can_return_only_source_location() -> None:
    output = '''
Error: provider returned an unknown sensitive diagnostic
  with data.oci_example.internal,
  on data.tf line 68, in data "oci_example" "internal":
'''

    assert classify_terraform_error(output) == "terraform_source:data.tf:68"


def test_run_quiet_can_add_only_classified_diagnostic() -> None:
    sensitive = 'Invalid value for variable\nvariable "operator_cidr"\nocid1.example.sensitive'

    def runner(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess(command, 1, "", sensitive)

    with pytest.raises(
        RuntimeError,
        match=r"^Terraform plan failed \[invalid_variable:operator_cidr\]$",
    ) as failure:
        run_quiet(
            ["terraform", "plan"],
            "Terraform plan",
            runner=runner,
            diagnostic_classifier=classify_terraform_error,
        )

    assert "ocid1" not in str(failure.value)


def test_run_quiet_writes_failure_detail_only_to_private_runtime_file(tmp_path) -> None:
    sensitive = "provider diagnostic with private topology"
    diagnostic_path = tmp_path / "runtime" / "terraform.log"

    def runner(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess(command, 1, "stdout detail", sensitive)

    with pytest.raises(RuntimeError, match=r"^Terraform plan failed$"):
        run_quiet(
            ["terraform", "plan"],
            "Terraform plan",
            runner=runner,
            diagnostic_path=diagnostic_path,
        )

    assert diagnostic_path.read_text(encoding="utf-8") == f"stdout detail\n{sensitive}\n"
    assert stat.S_IMODE(diagnostic_path.stat().st_mode) == 0o600
