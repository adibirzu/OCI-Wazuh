import json

from m11.discovery import build_preflight_snapshot


PROJECT = "oci-wazuh-demo"
FINGERPRINT = "a" * 64


def planned_resource(address: str, resource_type: str, name: str) -> dict:
    name_key = "display_name" if resource_type in {
        "oci_logging_log_group",
        "oci_logging_log",
        "oci_sch_service_connector",
    } else "name"
    return {
        "address": address,
        "mode": "managed",
        "type": resource_type,
        "values": {
            name_key: name,
            "freeform_tags": {
                "project": PROJECT,
                "configuration_fingerprint": FINGERPRINT,
            },
        },
    }


def plan(resources: list[dict]) -> dict:
    return {
        "planned_values": {
            "root_module": {
                "resources": resources[:1],
                "child_modules": [{"resources": resources[1:]}],
            }
        }
    }


def search_item(name: str, resource_type: str, *, state: str = "ACTIVE", fingerprint: str = FINGERPRINT) -> dict:
    return {
        "identifier": f"id-{name}",
        "display-name": name,
        "resource-type": resource_type,
        "lifecycle-state": state,
        "freeform-tags": {
            "project": PROJECT,
            "configuration_fingerprint": fingerprint,
        },
    }


def test_snapshot_derives_supported_expected_and_observed_resources() -> None:
    resources = [
        planned_resource("oci_identity_dynamic_group.demo", "oci_identity_dynamic_group", f"{PROJECT}-dg"),
        planned_resource("module.sch.oci_sch_service_connector.flow", "oci_sch_service_connector", f"{PROJECT}-flow"),
        planned_resource("oci_core_vcn.demo", "oci_core_vcn", f"{PROJECT}-vcn"),
    ]
    search = [
        search_item(f"{PROJECT}-dg", "DynamicGroup"),
        search_item(f"{PROJECT}-flow", "ServiceConnector"),
    ]

    snapshot = build_preflight_snapshot(plan(resources), search, PROJECT, connector_limit=3)

    assert [item.address for item in snapshot.expected] == [
        "oci_identity_dynamic_group.demo",
        "module.sch.oci_sch_service_connector.flow",
    ]
    assert len(snapshot.observed) == 2
    assert snapshot.connector_capacity.limit == 3
    assert snapshot.connector_capacity.active_count == 1


def test_missing_or_mismatched_fingerprint_cannot_be_an_exact_match() -> None:
    resource = planned_resource(
        "oci_logging_log_group.demo",
        "oci_logging_log_group",
        f"{PROJECT}-logs",
    )
    search = [search_item(f"{PROJECT}-logs", "LogGroup", fingerprint="")]

    snapshot = build_preflight_snapshot(plan([resource]), search, PROJECT, connector_limit=1)

    assert snapshot.expected[0].configuration == {"fingerprint": FINGERPRINT}
    assert snapshot.observed[0].configuration == {"fingerprint": ""}


def test_deleted_connectors_do_not_consume_active_capacity() -> None:
    resource = planned_resource(
        "oci_sch_service_connector.demo",
        "oci_sch_service_connector",
        f"{PROJECT}-connector",
    )
    search = [
        search_item(f"{PROJECT}-connector", "ServiceConnector", state="DELETED"),
        search_item(f"{PROJECT}-old", "ServiceConnector", state="ACTIVE"),
    ]

    snapshot = build_preflight_snapshot(plan([resource]), search, PROJECT, connector_limit=2)

    assert snapshot.connector_capacity.active_count == 1
    assert snapshot.observed[0].lifecycle_state == "DELETED"


def test_snapshot_rejects_missing_limit_or_project_fingerprint() -> None:
    resource = planned_resource(
        "oci_identity_policy.demo",
        "oci_identity_policy",
        f"{PROJECT}-policy",
    )
    resource["values"]["freeform_tags"].pop("configuration_fingerprint")

    try:
        build_preflight_snapshot(plan([resource]), [], PROJECT, connector_limit=1)
    except ValueError as exc:
        assert "fingerprint" in str(exc)
    else:
        raise AssertionError("missing fingerprint must fail closed")

    try:
        build_preflight_snapshot(plan([]), [], PROJECT, connector_limit=0)
    except ValueError as exc:
        assert "connector_limit" in str(exc)
    else:
        raise AssertionError("missing connector capacity must fail closed")


def test_configuration_only_disabled_resources_are_not_expected() -> None:
    enabled = planned_resource(
        "oci_identity_policy.demo",
        "oci_identity_policy",
        f"{PROJECT}-policy",
    )
    disabled = {
        "address": "oci_objectstorage_object.windows_install",
        "mode": "managed",
        "type": "oci_objectstorage_object",
        "values": None,
    }

    snapshot = build_preflight_snapshot(plan([enabled, disabled]), [], PROJECT, connector_limit=1)

    assert [resource.address for resource in snapshot.expected] == ["oci_identity_policy.demo"]


def test_object_storage_objects_use_ownership_metadata_instead_of_tags() -> None:
    resource = {
        "address": "oci_objectstorage_object.bootstrap",
        "mode": "managed",
        "type": "oci_objectstorage_object",
        "values": {
            "object": f"{PROJECT}-bootstrap.json",
            "metadata": {
                "project": PROJECT,
                "configuration_fingerprint": FINGERPRINT,
            },
        },
    }

    snapshot = build_preflight_snapshot(plan([resource]), [], PROJECT, connector_limit=1)

    assert snapshot.expected[0].tags["project"] == PROJECT
    assert snapshot.expected[0].configuration == {"fingerprint": FINGERPRINT}


def test_dashboard_import_reads_name_and_tags_from_import_details() -> None:
    resource = {
        "address": "oci_management_dashboard_management_dashboards_import.wazuh[0]",
        "mode": "managed",
        "type": "oci_management_dashboard_management_dashboards_import",
        "values": {
            "import_details": json.dumps(
                {
                    "dashboards": [
                        {
                            "displayName": f"{PROJECT}-correlation",
                            "freeformTags": {
                                "project": PROJECT,
                                "configuration_fingerprint": FINGERPRINT,
                            },
                        }
                    ]
                }
            )
        },
    }

    snapshot = build_preflight_snapshot(plan([resource]), [], PROJECT, connector_limit=1)

    assert snapshot.expected[0].name == f"{PROJECT}-correlation"
    assert snapshot.expected[0].tags["configuration_fingerprint"] == FINGERPRINT
