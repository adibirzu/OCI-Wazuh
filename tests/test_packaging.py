import hashlib
import json
import zipfile
from pathlib import Path

from m11.packaging import build_orm_package
from m11.redaction import find_sensitive_values


ROOT = Path(__file__).resolve().parents[1]


def zip_names(path: Path) -> set[str]:
    with zipfile.ZipFile(path) as archive:
        return set(archive.namelist())


def test_package_is_allowlisted_complete_and_reproducible(tmp_path: Path) -> None:
    first = build_orm_package(ROOT, tmp_path / "first")
    second = build_orm_package(ROOT, tmp_path / "second")

    assert first.zip_path.read_bytes() == second.zip_path.read_bytes()
    names = zip_names(first.zip_path)
    assert "schema.yaml" in names
    assert "main.tf" in names
    assert "bootstrap/oci-wazuh-bootstrap.json" in names
    assert "bootstrap/manifest.json" in names
    assert "README.md" in names
    assert "modules/goad-v3/LICENSE.upstream" in names
    assert "terraform.tfvars" not in names
    assert not any(name.startswith("ansible/") or name.startswith("scripts/") for name in names)
    assert not any(name.startswith("modules/vault/") or name.startswith("modules/agents-linux/") for name in names)
    assert not any("artifacts/" in name for name in names)
    assert not any("__pycache__" in name or name.endswith(".pyc") for name in names)

    digest = hashlib.sha256(first.zip_path.read_bytes()).hexdigest()
    assert first.checksum_path.read_text(encoding="utf-8") == f"{digest}  {first.zip_path.name}\n"
    manifest = json.loads(first.manifest_path.read_text(encoding="utf-8"))
    assert manifest["sha256"] == digest
    assert manifest["file_count"] == len(names)
    assert manifest["files"] == sorted(names)


def test_bootstrap_manifest_covers_every_bundled_asset(tmp_path: Path) -> None:
    result = build_orm_package(ROOT, tmp_path)

    with zipfile.ZipFile(result.zip_path) as archive:
        bundle = json.loads(archive.read("bootstrap/oci-wazuh-bootstrap.json"))
        manifest = json.loads(archive.read("bootstrap/manifest.json"))

    assert bundle["format"] == "oci-wazuh-bootstrap-v1"
    assert set(bundle["files"]) == set(manifest["assets"])
    for relative_path, encoded in bundle["files"].items():
        decoded = __import__("base64").b64decode(encoded)
        assert hashlib.sha256(decoded).hexdigest() == manifest["assets"][relative_path]


def test_public_package_contains_no_sensitive_topology(tmp_path: Path) -> None:
    result = build_orm_package(ROOT, tmp_path)

    findings: dict[str, list[str]] = {}
    with zipfile.ZipFile(result.zip_path) as archive:
        for name in archive.namelist():
            if Path(name).suffix not in {".tf", ".tftpl", ".md", ".py", ".sh", ".yaml", ".yml", ".json", ".xml", ".ps1"}:
                continue
            labels = find_sensitive_values(archive.read(name).decode("utf-8", errors="replace"))
            if labels:
                findings[name] = labels

    assert findings == {}
