#!/usr/bin/env python3
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ARTIFACT = ROOT / "artifacts/validation/dashboard-assets.json"
LA_QUERIES = ROOT / "dashboards/log-analytics/oci-wazuh-dashboard-queries.json"
WAZUH_VIEWS = ROOT / "dashboards/wazuh/oci-wazuh-views.md"

REQUIRED_QUERY_IDS = {
    "source_inventory",
    "vcn_flow_actions",
    "vcn_rejects_by_pair",
    "oci_audit_events",
    "oci_audit_users",
    "windows_sysmon_event_ids",
    "windows_sysmon_network",
    "linux_host_logs",
    "wazuh_alert_volume",
    "wazuh_alert_raw_search",
}

REQUIRED_SOURCES = {
    "OCI VCN Flow Unified Schema Logs",
    "OCI Audit Logs",
    "Windows Sysmon Events",
    "Linux Syslog Logs",
    "Linux Secure Logs",
    "OCI Unified Schema Logs",
    "wazuh-alerts-json",
}

REQUIRED_WAZUH_TERMS = {
    "wazuh-alerts-*",
    "100000",
    "100099",
    "100100",
    "100199",
    "OCI Audit Detections",
    "VCN Flow Detections",
    "GOAD Windows and Sysmon",
}


def main():
    failures = []
    payload = json.loads(LA_QUERIES.read_text(encoding="utf-8"))
    queries = payload.get("queries", [])
    ids = [query.get("id") for query in queries]

    duplicate_ids = sorted({query_id for query_id in ids if ids.count(query_id) > 1})
    missing_ids = sorted(REQUIRED_QUERY_IDS.difference(ids))
    if duplicate_ids:
        failures.append(f"duplicate_query_ids={','.join(duplicate_ids)}")
    if missing_ids:
        failures.append(f"missing_query_ids={','.join(missing_ids)}")

    query_text = json.dumps(payload)
    missing_sources = sorted(source for source in REQUIRED_SOURCES if source not in query_text)
    if missing_sources:
        failures.append(f"missing_log_sources={','.join(missing_sources)}")

    for query in queries:
        for field in ("id", "title", "visualization", "query"):
            if not query.get(field):
                failures.append(f"query.{query.get('id', '<missing-id>')}.missing_{field}")

    wazuh_text = WAZUH_VIEWS.read_text(encoding="utf-8")
    missing_wazuh_terms = sorted(term for term in REQUIRED_WAZUH_TERMS if term not in wazuh_text)
    if missing_wazuh_terms:
        failures.append(f"missing_wazuh_terms={','.join(missing_wazuh_terms)}")

    result = {
        "log_analytics_query_count": len(queries),
        "wazuh_view_doc": str(WAZUH_VIEWS.relative_to(ROOT)),
        "failures": failures,
        "ok": not failures,
    }
    ARTIFACT.parent.mkdir(parents=True, exist_ok=True)
    ARTIFACT.write_text(json.dumps(result, indent=2), encoding="utf-8")

    if failures:
        for failure in failures:
            print(failure)
        return 1

    print(f"dashboard_assets=ready queries={len(queries)} artifact={ARTIFACT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
