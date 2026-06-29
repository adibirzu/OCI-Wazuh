from m11.residuals import logical_residuals


PROJECT = "oci-wazuh-demo"


def test_residual_inventory_combines_search_and_explicit_log_analytics_without_ids() -> None:
    search = {
        "data": {
            "items": [
                {
                    "identifier": "private-vcn-id",
                    "resource-type": "Vcn",
                    "display-name": f"{PROJECT}-vcn",
                    "lifecycle-state": "AVAILABLE",
                    "freeform-tags": {"project": PROJECT},
                },
                {
                    "identifier": "deleted-id",
                    "resource-type": "Stream",
                    "display-name": f"{PROJECT}-old",
                    "lifecycle-state": "DELETED",
                    "freeform-tags": {"project": PROJECT},
                },
            ]
        }
    }
    log_analytics = {
        "data": {
            "items": [
                {
                    "id": "private-log-group-id",
                    "display-name": f"{PROJECT}-log-analytics",
                    "freeform-tags": {"project": PROJECT},
                },
                {
                    "id": "external-id",
                    "display-name": "shared",
                    "freeform-tags": {},
                },
            ]
        }
    }

    residuals = logical_residuals(search, log_analytics, PROJECT)

    assert residuals == [
        {"identifier": f"LogAnalyticsLogGroup:{PROJECT}-log-analytics"},
        {"identifier": f"Vcn:{PROJECT}-vcn"},
    ]
    assert "private" not in str(residuals)
