import gzip
import json
from pathlib import Path

from wazuh.consumer.oci_log_consumer import (
    detect_source,
    iter_json_records,
    load_seen,
    mark_seen,
    normalize_event,
    parse_json_payload,
)


def test_consumer_parses_gzip_batches_and_normalizes_audit_and_flow() -> None:
    payload = {
        "entries": [
            {"data": {"eventType": "com.oraclecloud.audit.synthetic", "principalName": "tester"}},
            {"data": {"srcaddr": "192.0.2.1", "dstaddr": "192.0.2.2", "action": "ACCEPT"}},
        ]
    }
    encoded = gzip.compress(json.dumps(payload).encode())

    records = list(iter_json_records(parse_json_payload(encoded)))

    assert [detect_source(record) for record in records] == ["audit", "flow"]
    audit = normalize_event(records[0])
    flow = normalize_event(records[1])
    assert audit and audit["source"] == "audit" and audit["principalName"] == "tester"
    assert flow and flow["source"] == "flow" and flow["action"] == "ACCEPT"


def test_consumer_state_is_append_only_and_ignores_blank_lines(tmp_path: Path) -> None:
    state_file = tmp_path / "state" / "seen.txt"

    mark_seen(state_file, "object-a")
    mark_seen(state_file, "object-b")
    state_file.write_text(state_file.read_text(encoding="utf-8") + "\n", encoding="utf-8")

    assert load_seen(state_file) == {"object-a", "object-b"}
    assert load_seen(tmp_path / "missing") == set()
