from m11.reconciliation import (
    ConnectorCapacity,
    ExpectedResource,
    ObservedResource,
    decide_connector_capacity,
    reconcile_resources,
)


PROJECT = "oci-wazuh-demo"


def expected(resource_type: str = "oci_identity_dynamic_group") -> ExpectedResource:
    return ExpectedResource(
        address="oci_identity_dynamic_group.wazuh",
        resource_type=resource_type,
        name=f"{PROJECT}-wazuh",
        tags={"project": PROJECT},
        configuration={"matching_rule": "instance.compartment.id = '<COMPARTMENT>'"},
    )


def observed(**overrides: object) -> ObservedResource:
    values = {
        "resource_id": "synthetic-resource-id",
        "resource_type": "oci_identity_dynamic_group",
        "name": f"{PROJECT}-wazuh",
        "lifecycle_state": "ACTIVE",
        "tags": {"project": PROJECT},
        "configuration": {"matching_rule": "instance.compartment.id = '<COMPARTMENT>'"},
        "importable": True,
    }
    values.update(overrides)
    return ObservedResource(**values)


def test_clean_state_classifies_expected_resource_for_creation() -> None:
    report = reconcile_resources([expected()], [], PROJECT)

    assert report.safe_to_apply is True
    assert report.decisions[0].action == "create"


def test_partial_state_imports_one_owned_exact_fingerprint_match() -> None:
    report = reconcile_resources([expected()], [observed()], PROJECT)

    assert report.safe_to_apply is True
    assert report.decisions[0].action == "import"
    assert report.decisions[0].resource_id == "synthetic-resource-id"


def test_name_only_external_collision_blocks_without_adoption() -> None:
    candidate = observed(tags={}, configuration={"matching_rule": "different"})

    report = reconcile_resources([expected()], [candidate], PROJECT)

    assert report.safe_to_apply is False
    assert report.decisions[0].action == "externally_owned"
    assert report.decisions[0].resource_id is None


def test_owned_drift_ambiguity_and_provider_import_defect_block() -> None:
    drifted = observed(configuration={"matching_rule": "different"})
    duplicate = observed(resource_id="duplicate-id")
    not_importable = observed(importable=False)

    drift_report = reconcile_resources([expected()], [drifted], PROJECT)
    ambiguous_report = reconcile_resources([expected()], [observed(), duplicate], PROJECT)
    import_report = reconcile_resources([expected()], [not_importable], PROJECT)

    assert drift_report.decisions[0].reason == "owned_configuration_mismatch"
    assert ambiguous_report.decisions[0].reason == "ambiguous_exact_matches"
    assert import_report.decisions[0].reason == "provider_import_unsupported"
    assert not drift_report.safe_to_apply
    assert not ambiguous_report.safe_to_apply
    assert not import_report.safe_to_apply


def test_deleted_candidates_are_ignored() -> None:
    report = reconcile_resources(
        [expected()],
        [observed(lifecycle_state="DELETED")],
        PROJECT,
    )

    assert report.safe_to_apply is True
    assert report.decisions[0].action == "create"


def test_connector_capacity_reuses_exact_match_or_blocks_before_apply() -> None:
    connector_expected = expected("oci_sch_service_connector")
    connector = observed(resource_type="oci_sch_service_connector")

    reused = decide_connector_capacity(
        connector_expected,
        [connector],
        ConnectorCapacity(limit=2, active_count=2),
        PROJECT,
    )
    exhausted = decide_connector_capacity(
        connector_expected,
        [],
        ConnectorCapacity(limit=2, active_count=2),
        PROJECT,
    )

    assert reused.action == "import"
    assert exhausted.action == "blocked"
    assert exhausted.reason == "service_connector_quota_exhausted"
    assert exhausted.resource_id is None
