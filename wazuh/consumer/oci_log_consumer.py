#!/usr/bin/env python3
"""Consume OCI log events and write normalized JSON lines for Wazuh."""

from __future__ import annotations

import argparse
import base64
import gzip
import json
import os
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable


def load_oci_config(profile: str | None, use_instance_principal: bool) -> tuple[dict[str, Any], Any | None]:
    import oci

    if use_instance_principal:
        signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
        return {"region": os.environ.get("OCI_REGION", signer.region)}, signer
    return oci.config.from_file(profile_name=profile), None


def compact_json(data: dict[str, Any]) -> str:
    return json.dumps(data, separators=(",", ":"), sort_keys=True)


def parse_json_payload(payload: bytes | str) -> Any:
    if isinstance(payload, bytes):
        if payload[:2] == b"\x1f\x8b":
            payload = gzip.decompress(payload)
        text = payload.decode("utf-8", errors="replace")
    else:
        text = payload
    text = text.strip()
    if not text:
        return None
    return json.loads(text)


def iter_json_records(payload: Any) -> Iterable[dict[str, Any]]:
    if payload is None:
        return
    if isinstance(payload, list):
        for item in payload:
            yield from iter_json_records(item)
        return
    if not isinstance(payload, dict):
        return

    if isinstance(payload.get("entries"), list):
        for item in payload["entries"]:
            yield from iter_json_records(item)
        return
    if isinstance(payload.get("data"), list):
        for item in payload["data"]:
            yield from iter_json_records(item)
        return
    if isinstance(payload.get("logContent"), dict):
        yield payload["logContent"]
        return
    yield payload


def detect_source(raw: dict[str, Any], preferred: str | None = None) -> str | None:
    if preferred in {"audit", "flow"}:
        return preferred

    data = raw.get("data", raw)
    event_type = str(data.get("eventType") or raw.get("type") or raw.get("eventType") or "").lower()
    service = str(raw.get("source") or data.get("service") or data.get("serviceName") or "").lower()

    if "flowlogs" in event_type or {"srcaddr", "dstaddr", "action"}.issubset(data.keys()):
        return "flow"
    if "audit" in event_type or service == "audit" or data.get("principalName") or data.get("identity"):
        return "audit"
    return None


def normalize_event(raw: dict[str, Any], source: str | None = None) -> dict[str, Any] | None:
    data = raw.get("data", raw)
    detected_source = detect_source(raw, source)
    if detected_source is None:
        return None

    normalized = {
        "source": detected_source,
        "time": (
            data.get("eventTime")
            or data.get("time")
            or raw.get("time")
            or raw.get("eventTime")
            or datetime.now(timezone.utc).isoformat()
        ),
        "eventType": data.get("eventType") or data.get("type") or raw.get("type"),
        "principalName": data.get("principalName") or data.get("identity", {}).get("principalName"),
        "sourceIp": data.get("sourceIpAddress") or data.get("sourceIp") or data.get("clientIpAddress"),
        "compartmentId": data.get("compartmentId") or raw.get("compartmentId"),
        "raw": raw,
    }

    if detected_source == "flow":
        normalized.update({
            "srcaddr": data.get("srcaddr") or data.get("sourceAddress") or data.get("Source IP"),
            "dstaddr": data.get("dstaddr") or data.get("destinationAddress") or data.get("Destination IP"),
            "srcport": data.get("srcport") or data.get("sourcePort") or data.get("Source Port"),
            "dstport": data.get("dstport") or data.get("destinationPort") or data.get("Destination Port"),
            "protocol": data.get("protocol") or data.get("protocolNumber") or data.get("Protocol Number"),
            "action": data.get("action") or data.get("Action"),
            "bytes": data.get("bytes") or data.get("Bytes"),
            "packets": data.get("packets") or data.get("Packets"),
        })
    return {key: value for key, value in normalized.items() if value is not None}


def write_normalized(records: Iterable[dict[str, Any]], output_dir: Path, forced_source: str | None = None) -> int:
    output_dir.mkdir(parents=True, exist_ok=True)
    handles: dict[str, Any] = {}
    count = 0
    try:
        for raw in records:
            normalized = normalize_event(raw, forced_source)
            if normalized is None:
                continue
            source = normalized["source"]
            if source not in handles:
                handles[source] = (output_dir / f"{source}.json").open("a", encoding="utf-8")
            handles[source].write(compact_json(normalized) + "\n")
            handles[source].flush()
            count += 1
    finally:
        for handle in handles.values():
            handle.close()
    return count


def normalize_file(input_path: Path, output_dir: Path, source: str | None) -> int:
    def records() -> Iterable[dict[str, Any]]:
        with input_path.open("rb") as source_file:
            for line in source_file:
                if not line.strip():
                    continue
                yield from iter_json_records(parse_json_payload(line))

    return write_normalized(records(), output_dir, source)


def stream_records(args: argparse.Namespace) -> Iterable[dict[str, Any]]:
    import oci

    config, signer = load_oci_config(args.oci_profile, args.instance_principal)
    admin_client = oci.streaming.StreamAdminClient(config, signer=signer)
    stream = admin_client.get_stream(args.stream_id).data
    endpoint = args.stream_endpoint or stream.messages_endpoint
    stream_client = oci.streaming.StreamClient(config, signer=signer, service_endpoint=endpoint)
    cursor_details = oci.streaming.models.CreateGroupCursorDetails(
        group_name=args.group_name,
        instance_name=args.instance_name,
        type=args.cursor_type,
        commit_on_get=True,
    )
    cursor = stream_client.create_group_cursor(args.stream_id, cursor_details).data.value

    while True:
        response = stream_client.get_messages(args.stream_id, cursor, limit=args.limit)
        cursor = response.headers["opc-next-cursor"]
        if not response.data:
            time.sleep(args.poll_seconds)
            continue
        for message in response.data:
            payload = base64.b64decode(message.value.encode())
            yield from iter_json_records(parse_json_payload(payload))


def load_seen(path: Path) -> set[str]:
    if not path.exists():
        return set()
    return {line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()}


def mark_seen(path: Path, object_name: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fh:
        fh.write(object_name + "\n")


def object_storage_records(args: argparse.Namespace) -> Iterable[dict[str, Any]]:
    import oci

    config, signer = load_oci_config(args.oci_profile, args.instance_principal)
    client = oci.object_storage.ObjectStorageClient(config, signer=signer)
    seen = load_seen(args.state_file)

    while True:
        objects = oci.pagination.list_call_get_all_results(
            client.list_objects,
            args.object_namespace,
            args.object_bucket,
            prefix=args.object_prefix,
        ).data.objects
        progressed = False
        for obj in sorted(objects, key=lambda item: item.name):
            if obj.name in seen:
                continue
            body = client.get_object(args.object_namespace, args.object_bucket, obj.name).data.content
            yield from iter_json_records(parse_json_payload(body))
            seen.add(obj.name)
            mark_seen(args.state_file, obj.name)
            progressed = True
        if not progressed:
            time.sleep(args.poll_seconds)


def audit_compartment_ids(config: dict[str, Any], signer: Any | None, root_compartment_id: str, include_subtree: bool) -> list[str]:
    if not include_subtree:
        return [root_compartment_id]

    import oci

    client = oci.identity.IdentityClient(config, signer=signer)
    compartment_ids = [root_compartment_id]
    try:
        compartments = oci.pagination.list_call_get_all_results(
            client.list_compartments,
            root_compartment_id,
            compartment_id_in_subtree=True,
            access_level="ANY",
        ).data
    except Exception as exc:  # pragma: no cover - defensive fallback for least-privilege tenancies
        print(f"compartment discovery failed; polling root only: {exc}", file=sys.stderr)
        return compartment_ids

    for compartment in compartments:
        compartment_id = getattr(compartment, "id", None)
        lifecycle_state = str(getattr(compartment, "lifecycle_state", "")).upper()
        if compartment_id and lifecycle_state != "DELETED":
            compartment_ids.append(compartment_id)
    return list(dict.fromkeys(compartment_ids))


def direct_api_records(args: argparse.Namespace) -> Iterable[dict[str, Any]]:
    import oci

    config, signer = load_oci_config(args.oci_profile, args.instance_principal)
    client = oci.audit.AuditClient(config, signer=signer)
    seen = load_seen(args.state_file)
    compartments = audit_compartment_ids(config, signer, args.compartment_id, args.compartment_id_in_subtree)

    while True:
        end_time = datetime.now(timezone.utc)
        start_time = end_time - timedelta(minutes=args.direct_api_lookback_minutes)
        for compartment_id in compartments:
            try:
                events = oci.pagination.list_call_get_all_results(
                    client.list_events,
                    compartment_id,
                    start_time=start_time,
                    end_time=end_time,
                ).data
            except Exception as exc:  # pragma: no cover - keeps one denied compartment from killing ingestion
                print(f"audit poll failed for compartment {compartment_id}: {exc}", file=sys.stderr)
                continue
            for event in events:
                event_id = getattr(event, "event_id", None) or getattr(event, "id", None)
                if event_id and event_id in seen:
                    continue
                raw = oci.util.to_dict(event)
                if event_id:
                    seen.add(event_id)
                    mark_seen(args.state_file, event_id)
                yield raw
        time.sleep(args.poll_seconds)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["streaming", "object_storage", "direct_api", "file"], default="streaming")
    parser.add_argument("--source", choices=["audit", "flow", "auto"], default="auto")
    parser.add_argument("--input-file", type=Path, help="Development/test input JSONL file.")
    parser.add_argument("--output-dir", type=Path, default=Path("/var/ossec/logs/oci"))
    parser.add_argument("--state-file", type=Path, default=Path("/var/lib/oci-wazuh-consumer/state.txt"))
    parser.add_argument("--oci-profile")
    parser.add_argument("--instance-principal", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--poll-seconds", type=int, default=10)
    parser.add_argument("--limit", type=int, default=100)
    parser.add_argument("--stream-id")
    parser.add_argument("--stream-endpoint")
    parser.add_argument("--group-name", default="oci-wazuh-demo")
    parser.add_argument("--instance-name", default="wazuh-aio")
    parser.add_argument("--cursor-type", choices=["TRIM_HORIZON", "LATEST"], default="TRIM_HORIZON")
    parser.add_argument("--object-namespace")
    parser.add_argument("--object-bucket")
    parser.add_argument("--object-prefix", default="oci-logs/")
    parser.add_argument("--compartment-id")
    parser.add_argument("--compartment-id-in-subtree", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument("--direct-api-lookback-minutes", type=int, default=15)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    forced_source = None if args.source == "auto" else args.source

    if args.input_file:
        count = normalize_file(args.input_file, args.output_dir, forced_source)
        print(f"normalized={count}")
        return 0

    if args.mode == "streaming":
        if not args.stream_id:
            print("--stream-id is required for streaming mode", file=sys.stderr)
            return 2
        records = stream_records(args)
    elif args.mode == "object_storage":
        if not args.object_namespace or not args.object_bucket:
            print("--object-namespace and --object-bucket are required for object_storage mode", file=sys.stderr)
            return 2
        records = object_storage_records(args)
    elif args.mode == "direct_api":
        if not args.compartment_id:
            print("--compartment-id is required for direct_api mode", file=sys.stderr)
            return 2
        records = direct_api_records(args)
    else:
        print("--input-file is required for file mode", file=sys.stderr)
        return 2

    total = 0
    for record in records:
        total += write_normalized([record], args.output_dir, forced_source)
    return 0 if total >= 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
