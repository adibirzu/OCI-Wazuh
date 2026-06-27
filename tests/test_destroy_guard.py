import json

from m11.destroy_guard import evaluate_destroy_plan, wait_for_zero_residuals


def change(address: str, resource_type: str, before: dict) -> dict:
    return {
        "address": address,
        "type": resource_type,
        "change": {"actions": ["delete"], "before": before},
    }


def test_guard_accepts_tagged_named_and_owned_child_deletes() -> None:
    project = "oci-wazuh-demo"
    nsg_id = "ocid1.networksecuritygroup.oc1..synthetic"
    plan = {
        "resource_changes": [
            change("oci_core_vcn.lab", "oci_core_vcn", {"id": "vcn", "display_name": f"{project}-vcn"}),
            change(
                "oci_core_network_security_group.lab",
                "oci_core_network_security_group",
                {"id": nsg_id, "display_name": "unimportant", "freeform_tags": {"project": project}},
            ),
            change(
                "oci_core_network_security_group_security_rule.child",
                "oci_core_network_security_group_security_rule",
                {"network_security_group_id": nsg_id},
            ),
            change(
                "oci_objectstorage_bucket.bootstrap",
                "oci_objectstorage_bucket",
                {"id": "bucket-id", "name": f"{project}-bootstrap"},
            ),
            change(
                "oci_objectstorage_object.bootstrap",
                "oci_objectstorage_object",
                {"bucket": f"{project}-bootstrap", "object": "bootstrap/manifest.json"},
            ),
            change("random_id.bootstrap", "random_id", {"id": "deadbeef"}),
            change(
                "oci_management_dashboard_management_dashboards_import.wazuh",
                "oci_management_dashboard_management_dashboards_import",
                {"import_details": json.dumps({"dashboards": [{"freeformTags": {"project": project}}]})},
            ),
        ]
    }

    result = evaluate_destroy_plan(plan, project)

    assert result["ok"] is True
    assert result["delete_count"] == 7
    assert result["blocked"] == []


def test_guard_blocks_unowned_delete() -> None:
    plan = {"resource_changes": [change("oci_core_vcn.shared", "oci_core_vcn", {"display_name": "shared-vcn"})]}

    result = evaluate_destroy_plan(plan, "oci-wazuh-demo")

    assert result["ok"] is False
    assert result["blocked"][0]["address"] == "oci_core_vcn.shared"


def test_residual_check_retries_until_zero_without_returning_identifiers() -> None:
    results = iter([["resource-a"], ["resource-a"], []])
    sleeps: list[float] = []

    report = wait_for_zero_residuals(
        lambda: next(results),
        attempts=3,
        interval_seconds=0.1,
        sleep=sleeps.append,
    )

    assert report == {"ok": True, "attempts": 3, "residual_count": 0}
    assert sleeps == [0.1, 0.1]


def test_residual_check_fails_closed_after_bounded_attempts() -> None:
    report = wait_for_zero_residuals(
        lambda: ["sensitive-resource-id"],
        attempts=2,
        interval_seconds=0,
        sleep=lambda _: None,
    )

    assert report == {"ok": False, "attempts": 2, "residual_count": 1}
    assert "sensitive-resource-id" not in str(report)
