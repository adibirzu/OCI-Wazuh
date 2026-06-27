from m11.redaction import find_runtime_topology, find_sensitive_values, redact_text


def test_redaction_covers_oci_identity_topology_and_personal_paths() -> None:
    source = "\n".join(
        [
            "resource=ocid1.instance.oc1.eu-test-1.syntheticidentifier",
            "public=130.61.12.34 private=10.42.1.8 egress=82.77.1.4",
            "namespace=fr4zqfimuxtr apm=aaaadhp5ewo4eaaaaaaaaafs7q",
            "path=/Users/person@example.com/private/config",
            "fingerprint=aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99",
        ]
    )

    redacted = redact_text(source)

    assert find_sensitive_values(redacted) == []
    assert "<OCI_OCID>" in redacted
    assert "<PUBLIC_IP>" in redacted
    assert "<PRIVATE_IP>" in redacted
    assert "${OCIR_TENANCY}" in redacted
    assert "<PERSONAL_PATH>" in redacted


def test_scanner_returns_pattern_labels_without_echoing_secret_values() -> None:
    findings = find_sensitive_values("ocid1.tenancy.oc1..synthetic 161.153.2.3")

    assert findings == ["oci_ocid", "public_ip"]


def test_runtime_artifact_scanner_rejects_any_ocid_or_ip_address() -> None:
    findings = find_runtime_topology("target=ocid1.log.oc1.region.synthetic address=192.0.2.10")

    assert findings == ["oci_ocid", "ip_address"]
    assert find_runtime_topology("target=<OCI_OCID> address=<REDACTED_IP>") == []
