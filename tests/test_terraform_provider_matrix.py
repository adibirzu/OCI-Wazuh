from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_provider_profile_is_nullable_for_profile_free_orm() -> None:
    versions = (ROOT / "terraform/versions.tf").read_text(encoding="utf-8")

    assert "config_file_profile = var.oci_config_profile != \"\" ? var.oci_config_profile : null" in versions
    assert 'default     = ""' in (ROOT / "terraform/variables.tf").read_text(encoding="utf-8")


def test_provider_null_list_fallbacks_have_explicit_overrides() -> None:
    data = (ROOT / "terraform/data.tf").read_text(encoding="utf-8")
    variables = (ROOT / "terraform/variables.tf").read_text(encoding="utf-8")

    for variable in (
        "availability_domain",
        "ol9_image_id",
        "ubuntu2404_image_id",
        "windows2022_image_id",
        "object_storage_namespace",
        "log_analytics_namespace",
    ):
        assert f'variable "{variable}"' in variables
    assert "coalesce(data.oci_identity_availability_domains.this.availability_domains, [])" in data
    assert "try(data.oci_core_images.ol9[0].images[0].id, \"\")" in data


def test_all_common_resource_tags_include_stable_configuration_fingerprint() -> None:
    locals_file = (ROOT / "terraform/locals.tf").read_text(encoding="utf-8")

    assert "configuration_fingerprint = sha256(jsonencode({" in locals_file
    assert "configuration_fingerprint = local.configuration_fingerprint" in locals_file
    for input_name in (
        "effective_ingestion_mode",
        "effective_windows_mode",
        "network_mode",
        "region",
        "wazuh_version",
    ):
        assert input_name in locals_file
