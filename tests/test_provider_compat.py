import pytest

from m11.provider_compat import OverrideEvidence, provider_environment, validate_overrides


def test_orm_is_profile_free_and_local_profile_is_explicit() -> None:
    assert provider_environment("orm", profile="cap") == {}
    assert provider_environment("local", profile="") == {}
    assert provider_environment("local", profile="cap") == {
        "OCI_CONFIG_PROFILE": "cap",
        "TF_VAR_oci_config_profile": "cap",
    }


def test_null_provider_results_accept_only_cli_verified_overrides() -> None:
    overrides = {
        "object_storage_namespace": "namespace",
        "availability_domain": "AD-1",
        "ol9_image_id": "image-ol9",
    }
    evidence = OverrideEvidence(
        provider_values={
            "object_storage_namespace": None,
            "availability_domain": None,
            "ol9_image_id": None,
        },
        cli_values=overrides,
    )

    assert validate_overrides(overrides, evidence) == overrides

    with pytest.raises(ValueError, match="CLI preflight did not verify"):
        validate_overrides(overrides, OverrideEvidence(provider_values={}, cli_values={}))


def test_conflicting_provider_and_override_value_is_rejected() -> None:
    with pytest.raises(ValueError, match="conflicts with provider discovery"):
        validate_overrides(
            {"availability_domain": "AD-2"},
            OverrideEvidence(
                provider_values={"availability_domain": "AD-1"},
                cli_values={"availability_domain": "AD-2"},
            ),
        )
