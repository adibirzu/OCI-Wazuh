from pathlib import Path

from m11.schema_contract import schema_variables, terraform_variables, validate_schema_parity


ROOT = Path(__file__).resolve().parents[1]


def test_orm_schema_matches_terraform_variable_names_and_types() -> None:
    schema_path = ROOT / "terraform" / "schema.yaml"
    variables_path = ROOT / "terraform" / "variables.tf"

    errors = validate_schema_parity(schema_path, variables_path)

    assert errors == []
    schema = schema_variables(schema_path)
    terraform = terraform_variables(variables_path)
    assert {
        "tenancy_ocid",
        "compartment_ocid",
        "network_mode",
        "ingestion_mode",
        "windows_mode",
        "object_storage_namespace",
    } <= set(schema)
    assert schema["enable_log_analytics_bridge"] == "boolean"
    assert terraform["goad_instance_ocids"] == "map(string)"
    assert terraform["object_storage_namespace"] == "string"


def test_schema_parity_reports_missing_and_mismatched_variables(tmp_path: Path) -> None:
    schema = tmp_path / "schema.yaml"
    schema.write_text(
        "variables:\n  count:\n    type: string\n  absent:\n    type: string\n",
        encoding="utf-8",
    )
    variables = tmp_path / "variables.tf"
    variables.write_text('variable "count" {\n  type = number\n}\n', encoding="utf-8")

    errors = validate_schema_parity(schema, variables)

    assert "schema variable absent is not declared by Terraform" in errors
    assert "schema variable count has type string; Terraform type is number" in errors
