"""Reproducible, allowlist-only OCI Resource Manager packaging."""

from __future__ import annotations

import base64
import argparse
import hashlib
import json
import stat
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Iterable


ZIP_TIMESTAMP = (2020, 1, 1, 0, 0, 0)
BOOTSTRAP_ASSETS = (
    "wazuh/consumer/oci_log_consumer.py",
    "wazuh/decoders/oci-audit-decoders.xml",
    "wazuh/decoders/vcn-flowlog-decoders.xml",
    "wazuh/rules/local_rules.xml",
    "wazuh/rules/oci-audit-rules.xml",
    "wazuh/rules/vcn-flowlog-rules.xml",
    "wazuh/rules/windows-sysmon-rules.xml",
    "dashboards/log-analytics/oci-wazuh-dashboard-queries.json",
    "dashboards/wazuh/oci-wazuh-views.md",
)
ROOT_FILE_MAP = {
    "docs/ORM_RESOURCE_MANAGER_DEPLOYMENT.md": "README.md",
    "terraform/schema.yaml": "schema.yaml",
}
TREE_ALLOWLIST = (
    ("terraform", ("*.tf",)),
    ("terraform/modules/compute", ("*.tf", "*.tftpl")),
    ("terraform/modules/flowlogs", ("*.tf",)),
    ("terraform/modules/goad-v3", ("*.tf", "*.md", "LICENSE*")),
    ("terraform/modules/logging-audit", ("*.tf",)),
    ("terraform/modules/network", ("*.tf",)),
    ("terraform/modules/service-connector", ("*.tf",)),
    ("terraform/modules/streaming", ("*.tf",)),
    ("terraform/modules/wazuh-server", ("*.tf", "*.tftpl")),
    ("terraform/modules/windows-optional", ("*.tf", "*.tftpl", "*.ps1")),
    ("wazuh", ("*.py", "*.xml")),
    ("dashboards", ("*.json", "*.md", "*.ndjson")),
    ("windows", ("*.xml", "*.ps1")),
)


@dataclass(frozen=True)
class PackageResult:
    zip_path: Path
    checksum_path: Path
    manifest_path: Path


def _json_bytes(payload: object) -> bytes:
    return (json.dumps(payload, indent=2, sort_keys=True) + "\n").encode("utf-8")


def _allowed_tree_files(root: Path) -> Iterable[tuple[str, bytes]]:
    seen: set[str] = set()
    for base, patterns in TREE_ALLOWLIST:
        directory = root / base
        for pattern in patterns:
            candidates = directory.glob(pattern) if base == "terraform" else directory.rglob(pattern)
            for source in sorted(candidates):
                if not source.is_file():
                    continue
                relative = source.relative_to(root).as_posix()
                if relative in seen:
                    continue
                seen.add(relative)
                archive_path = relative.removeprefix("terraform/") if relative.startswith("terraform/") else relative
                if archive_path == "schema.yaml":
                    continue
                yield archive_path, source.read_bytes()


def _bootstrap_files(root: Path) -> tuple[bytes, bytes]:
    encoded: dict[str, str] = {}
    hashes: dict[str, str] = {}
    for relative in BOOTSTRAP_ASSETS:
        content = (root / relative).read_bytes()
        encoded[relative] = base64.b64encode(content).decode("ascii")
        hashes[relative] = hashlib.sha256(content).hexdigest()
    bundle = _json_bytes({"files": encoded, "format": "oci-wazuh-bootstrap-v1"})
    manifest = _json_bytes(
        {
            "assets": hashes,
            "bundle_sha256": hashlib.sha256(bundle).hexdigest(),
            "format": "oci-wazuh-bootstrap-manifest-v1",
        }
    )
    return bundle, manifest


def _entries(root: Path) -> dict[str, bytes]:
    entries = dict(_allowed_tree_files(root))
    for source, destination in ROOT_FILE_MAP.items():
        entries[destination] = (root / source).read_bytes()
    bundle, bootstrap_manifest = _bootstrap_files(root)
    entries["bootstrap/oci-wazuh-bootstrap.json"] = bundle
    entries["bootstrap/manifest.json"] = bootstrap_manifest
    return entries


def _zip_info(name: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(PurePosixPath(name).as_posix(), ZIP_TIMESTAMP)
    info.compress_type = zipfile.ZIP_DEFLATED
    executable = name.startswith("scripts/") and name.endswith(".sh")
    mode = stat.S_IFREG | (0o755 if executable else 0o644)
    info.external_attr = mode << 16
    info.create_system = 3
    return info


def build_orm_package(root: Path, output_directory: Path) -> PackageResult:
    root = Path(root).resolve()
    output_directory = Path(output_directory)
    output_directory.mkdir(parents=True, exist_ok=True)
    zip_path = output_directory / "oci-wazuh-orm-stack.zip"
    entries = _entries(root)
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name in sorted(entries):
            archive.writestr(_zip_info(name), entries[name], compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)

    digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    checksum_path = output_directory / f"{zip_path.name}.sha256"
    checksum_path.write_text(f"{digest}  {zip_path.name}\n", encoding="utf-8")
    manifest_path = output_directory / "oci-wazuh-orm-stack.manifest.json"
    manifest_path.write_bytes(
        _json_bytes(
            {
                "file_count": len(entries),
                "files": sorted(entries),
                "format": "oci-resource-manager-stack-v1",
                "sha256": digest,
            }
        )
    )
    return PackageResult(zip_path, checksum_path, manifest_path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = build_orm_package(args.root, args.output)
    print(f"orm_stack_zip={result.zip_path}")
    print(f"orm_stack_checksum={result.checksum_path}")
    print(f"orm_stack_manifest={result.manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
