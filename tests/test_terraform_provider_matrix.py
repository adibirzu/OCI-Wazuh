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


def test_flow_log_for_each_keys_do_not_depend_on_apply_time_resource_ids() -> None:
    flowlogs = (ROOT / "terraform/modules/flowlogs/main.tf").read_text(encoding="utf-8")
    variables = (ROOT / "terraform/variables.tf").read_text(encoding="utf-8")
    ingestion = (ROOT / "terraform/ingestion.tf").read_text(encoding="utf-8")

    assert "for idx, resource_id in var.resource_ids" in flowlogs
    assert "distinct(var.resource_ids)" not in flowlogs
    assert "if resource_id != \"\"" not in flowlogs
    assert "Every flow_log_resource_ids entry must be non-empty." in variables
    assert (
        "for_each       = toset(nonsensitive(keys(sensitive(local.sch_log_source_policy_scope_ids))))" in ingestion
    )
    assert "local.sch_log_source_policy_scope_ids[each.key]" in ingestion


def test_windows_install_object_ownership_metadata_is_plan_time_known() -> None:
    windows = (ROOT / "terraform/windows.tf").read_text(encoding="utf-8")
    install_block = windows.split('resource "oci_objectstorage_object" "windows_install"', 1)[1].split(
        'resource "oci_objectstorage_object" "windows_cleanup"',
        1,
    )[0]

    assert "project                   = var.project_name" in install_block
    assert "configuration_fingerprint = local.configuration_fingerprint" in install_block
    assert "sha256(local.windows_install_script)" not in install_block


def test_project_objects_remove_all_versions_during_destroy() -> None:
    bootstrap = (ROOT / "terraform/bootstrap.tf").read_text(encoding="utf-8")
    windows = (ROOT / "terraform/windows.tf").read_text(encoding="utf-8")

    assert bootstrap.count("delete_all_object_versions = true") == 2
    assert windows.count("delete_all_object_versions = true") == 2
