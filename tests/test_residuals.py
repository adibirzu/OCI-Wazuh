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


def test_dashboard_residuals_use_authoritative_dashboard_inventory_over_stale_search() -> None:
    stale_search = {
        "data": {
            "items": [
                {
                    "resource-type": "ManagementDashboard",
                    "display-name": f"{PROJECT}-correlation",
                    "lifecycle-state": "AVAILABLE",
                    "freeform-tags": {"project": PROJECT},
                },
                {
                    "resource-type": "ManagementSavedSearch",
                    "display-name": f"{PROJECT}-audit",
                    "lifecycle-state": "AVAILABLE",
                    "freeform-tags": {"project": PROJECT},
                },
            ]
        }
    }

    residuals = logical_residuals(
        stale_search,
        {"data": {"items": []}},
        PROJECT,
        {"data": {"items": []}},
        {"data": {"items": []}},
    )

    assert residuals == []
