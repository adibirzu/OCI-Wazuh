import argparse
import base64
import json
import sys
import urllib.error
from pathlib import Path
from types import SimpleNamespace

import pytest

from wazuh.consumer import oci_log_consumer as consumer


def args(**overrides):
    defaults = {
        "compartment_id": "compartment",
        "compartment_id_in_subtree": False,
        "cursor_type": "TRIM_HORIZON",
        "direct_api_lookback_minutes": 15,
        "group_name": "group",
        "instance_name": "instance",
        "instance_principal": True,
        "limit": 10,
        "mode": "file",
        "object_bucket": None,
        "object_namespace": None,
        "object_prefix": "prefix/",
        "oci_profile": None,
        "opensearch_audit_index_prefix": None,
        "opensearch_enabled": False,
        "opensearch_flow_index_prefix": None,
        "opensearch_password": None,
        "opensearch_url": None,
        "opensearch_username": None,
        "opensearch_verify_ssl": None,
        "output_dir": Path("output"),
        "poll_seconds": 0,
        "source": "auto",
        "state_file": Path("state.txt"),
        "stream_endpoint": None,
        "stream_id": None,
        "input_file": None,
    }
    return argparse.Namespace(**{**defaults, **overrides})


def fake_oci(**namespaces):
    return SimpleNamespace(**namespaces)


def test_config_environment_time_and_json_helpers(monkeypatch):
    signer = SimpleNamespace(region="region")
    fake = fake_oci(
        auth=SimpleNamespace(signers=SimpleNamespace(InstancePrincipalsSecurityTokenSigner=lambda: signer)),
        config=SimpleNamespace(from_file=lambda profile_name: {"profile": profile_name}),
    )
    monkeypatch.setitem(sys.modules, "oci", fake)
    monkeypatch.setenv("OCI_REGION", "override-region")

    assert consumer.load_oci_config(None, True) == ({"region": "override-region"}, signer)
    assert consumer.load_oci_config("TEAM", False) == ({"profile": "TEAM"}, None)
    assert consumer.compact_json({"b": 2, "a": 1}) == '{"a":1,"b":2}'
    assert consumer.env_bool("MISSING", default=True) is True
    monkeypatch.setenv("FLAG", " yes ")
    assert consumer.env_bool("FLAG") is True
    assert consumer.parse_event_time("2026-01-01T00:00:00Z").startswith("2026-01-01T00:00:00+")
    assert "+00:00" in consumer.parse_event_time("not-a-time")
    assert "+00:00" in consumer.parse_event_time(None)


def test_payload_record_and_normalization_variants():
    assert consumer.parse_json_payload("") is None
    with pytest.raises(json.JSONDecodeError):
        consumer.parse_json_payload("not-json")

    nested = {
        "entries": [
            {"logContent": {"source": "audit", "identity": {"principalName": "user"}}},
            {"data": [{"srcaddr": "192.0.2.1", "dstaddr": "192.0.2.2", "action": "REJECT"}]},
            "ignored",
        ]
    }
    records = list(consumer.iter_json_records(nested))
    assert len(records) == 2
    assert consumer.detect_source(records[0]) == "audit"
    assert consumer.detect_source(records[1]) == "flow"
    assert consumer.detect_source({}, preferred="flow") == "flow"
    assert consumer.detect_source({}) is None
    assert consumer.normalize_event({}) is None
    flow = consumer.normalize_event(records[1])
    assert flow and flow["srcaddr"] == "192.0.2.1" and flow["action"] == "REJECT"


def test_write_and_normalize_file_with_sink(tmp_path):
    indexed = []
    sink = SimpleNamespace(index=lambda batch: indexed.extend(batch))
    output = tmp_path / "out"
    records = [
        {"data": {"eventType": "audit", "principalName": "user"}},
        {"data": {"srcaddr": "192.0.2.1", "dstaddr": "192.0.2.2", "action": "ACCEPT"}},
        {},
    ]

    assert consumer.write_normalized(records, output, opensearch_sink=sink) == 2
    assert len(indexed) == 2
    assert len((output / "audit.json").read_text(encoding="utf-8").splitlines()) == 1
    assert len((output / "flow.json").read_text(encoding="utf-8").splitlines()) == 1

    source = tmp_path / "events.jsonl"
    source.write_text('\n{"eventType":"audit","principalName":"file-user"}\n', encoding="utf-8")
    assert consumer.normalize_file(source, tmp_path / "file-out", "audit") == 1


def test_opensearch_sink_configuration_document_and_bulk(monkeypatch, capsys):
    monkeypatch.delenv("OCI_WAZUH_OPENSEARCH_ENABLED", raising=False)
    assert consumer.OpenSearchSink.from_args(args()) is None
    monkeypatch.setenv("OCI_WAZUH_OPENSEARCH_ENABLED", "true")
    assert consumer.OpenSearchSink.from_args(args()) is None
    assert "incomplete" in capsys.readouterr().err

    sink = consumer.OpenSearchSink.from_args(
        args(
            opensearch_enabled=True,
            opensearch_url="https://search.example",
            opensearch_username="user",
            opensearch_password="secret",
            opensearch_verify_ssl=False,
            opensearch_audit_index_prefix="audit",
            opensearch_flow_index_prefix="flow",
        )
    )
    assert sink is not None
    record = {"source": "audit", "time": "2026-01-02T00:00:00Z", "eventType": "event"}
    assert sink.index_name(record) == "audit-2026.01.02"
    assert sink.document(record)["cloud"] == {"provider": "oci"}

    captured = []
    monkeypatch.setattr(sink, "post_bulk", lambda lines: captured.extend(lines))
    assert sink.index([record]) == 1
    assert len(captured) == 2

    class Response:
        def __enter__(self):
            return self

        def __exit__(self, *_):
            return False

        def read(self):
            return b'{"errors":true}'

    monkeypatch.setattr(sink.opener, "open", lambda *_args, **_kwargs: Response())
    consumer.OpenSearchSink.post_bulk(sink, [])
    consumer.OpenSearchSink.post_bulk(sink, ["{}"])
    assert "item errors" in capsys.readouterr().err
    monkeypatch.setattr(sink.opener, "open", lambda *_args, **_kwargs: (_ for _ in ()).throw(urllib.error.URLError("down")))
    consumer.OpenSearchSink.post_bulk(sink, ["{}"])
    assert "failed" in capsys.readouterr().err


def test_streaming_and_object_storage_generators(monkeypatch, tmp_path):
    stream_message = SimpleNamespace(value=base64.b64encode(b'{"eventType":"audit"}').decode())

    class StreamAdmin:
        def __init__(self, *_args, **_kwargs):
            pass

        def get_stream(self, _stream_id):
            return SimpleNamespace(data=SimpleNamespace(messages_endpoint="endpoint"))

    class StreamClient:
        def __init__(self, *_args, **_kwargs):
            pass

        def create_group_cursor(self, *_args, **_kwargs):
            return SimpleNamespace(data=SimpleNamespace(value="cursor"))

        def get_messages(self, *_args, **_kwargs):
            return SimpleNamespace(data=[stream_message], headers={"opc-next-cursor": "next"})

    objects = [SimpleNamespace(name="prefix/a.json"), SimpleNamespace(name="prefix/b.json")]

    class ObjectClient:
        def __init__(self, *_args, **_kwargs):
            pass

        def list_objects(self, *_args, **_kwargs):
            return None

        def get_object(self, _namespace, _bucket, name):
            return SimpleNamespace(data=SimpleNamespace(content=json.dumps({"name": name, "eventType": "audit"}).encode()))

    fake = fake_oci(
        streaming=SimpleNamespace(
            StreamAdminClient=StreamAdmin,
            StreamClient=StreamClient,
            models=SimpleNamespace(CreateGroupCursorDetails=lambda **kwargs: kwargs),
        ),
        object_storage=SimpleNamespace(ObjectStorageClient=ObjectClient),
        pagination=SimpleNamespace(
            list_call_get_all_results=lambda *_args, **_kwargs: SimpleNamespace(data=SimpleNamespace(objects=objects))
        ),
    )
    monkeypatch.setitem(sys.modules, "oci", fake)
    monkeypatch.setattr(consumer, "load_oci_config", lambda *_args: ({}, None))

    stream = consumer.stream_records(args(stream_id="stream"))
    assert next(stream)["eventType"] == "audit"
    stream.close()

    state = tmp_path / "seen.txt"
    object_records = consumer.object_storage_records(
        args(object_namespace="namespace", object_bucket="bucket", state_file=state)
    )
    assert [next(object_records)["name"], next(object_records)["name"]] == ["prefix/a.json", "prefix/b.json"]
    object_records.close()
    assert consumer.load_seen(state) == {"prefix/a.json"}


def test_audit_compartment_discovery_and_direct_api(monkeypatch, tmp_path):
    compartments = [
        SimpleNamespace(id="child", lifecycle_state="ACTIVE"),
        SimpleNamespace(id="deleted", lifecycle_state="DELETED"),
        SimpleNamespace(id="root", lifecycle_state="ACTIVE"),
    ]
    event = SimpleNamespace(event_id="event-1", event_type="synthetic")

    class IdentityClient:
        def __init__(self, *_args, **_kwargs):
            pass

        def list_compartments(self, *_args, **_kwargs):
            return None

    class AuditClient:
        def __init__(self, *_args, **_kwargs):
            pass

        def list_events(self, *_args, **_kwargs):
            return None

    def all_results(call, *_args, **_kwargs):
        data = compartments if getattr(call, "__name__", "") == "list_compartments" else [event]
        return SimpleNamespace(data=data)

    fake = fake_oci(
        identity=SimpleNamespace(IdentityClient=IdentityClient),
        audit=SimpleNamespace(AuditClient=AuditClient),
        pagination=SimpleNamespace(list_call_get_all_results=all_results),
        util=SimpleNamespace(to_dict=lambda value: {"eventType": value.event_type, "id": value.event_id}),
    )
    monkeypatch.setitem(sys.modules, "oci", fake)
    monkeypatch.setattr(consumer, "load_oci_config", lambda *_args: ({}, None))

    assert consumer.audit_compartment_ids({}, None, "root", False) == ["root"]
    assert consumer.audit_compartment_ids({}, None, "root", True) == ["root", "child"]
    records = consumer.direct_api_records(
        args(compartment_id="root", state_file=tmp_path / "audit-seen.txt")
    )
    assert next(records) == {"eventType": "synthetic", "id": "event-1"}
    records.close()


@pytest.mark.parametrize(
    ("mode", "expected"),
    [("streaming", 2), ("object_storage", 2), ("direct_api", 2), ("file", 2)],
)
def test_main_rejects_incomplete_mode_arguments(monkeypatch, mode, expected):
    monkeypatch.setattr(consumer, "parse_args", lambda: args(mode=mode, compartment_id=None))
    monkeypatch.setattr(consumer.OpenSearchSink, "from_args", lambda _args: None)
    assert consumer.main() == expected


def test_parse_args_and_main_file_mode(monkeypatch, tmp_path, capsys):
    source = tmp_path / "input.jsonl"
    source.write_text('{"eventType":"audit"}\n', encoding="utf-8")
    monkeypatch.setattr(sys, "argv", ["consumer", "--mode", "file", "--input-file", str(source), "--output-dir", str(tmp_path / "out")])
    parsed = consumer.parse_args()
    assert parsed.mode == "file" and parsed.input_file == source
    monkeypatch.setattr(consumer, "parse_args", lambda: parsed)
    assert consumer.main() == 0
    assert "normalized=1" in capsys.readouterr().out
