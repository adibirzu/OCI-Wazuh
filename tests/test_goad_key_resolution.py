from pathlib import Path


SOURCE = (Path(__file__).parents[1] / "scripts/goad-wazuh.sh").read_text()


def test_template_private_key_fallback_is_removed():
    assert "template/provider/oci/ssh_keys/ubuntu-jumpbox.pem" not in SOURCE
    assert "ad/GOAD/providers/oci/ssh_keys/ubuntu-jumpbox.pem" not in SOURCE


def test_workspace_selection_is_explicit_and_metadata_matched():
    assert "GOAD_INSTANCE_ID" in SOURCE
    assert "GOAD_WORKSPACE_PATH" in SOURCE
    assert "key_matches_jumpbox_metadata" in SOURCE
    assert "No unique GOAD workspace key matches deployed jumpbox metadata" in SOURCE
