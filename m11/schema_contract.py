"""Lightweight schema.yaml to Terraform variable contract validation."""

from __future__ import annotations

import re
from pathlib import Path

import yaml


TERRAFORM_TO_SCHEMA_TYPES = {
    "bool": "boolean",
    "number": "number",
    "string": "string",
    "list(string)": "array",
    "set(string)": "array",
    "map(string)": "object",
}


def _compact_type(value: str) -> str:
    return re.sub(r"\s+", "", value)


def _variable_blocks(text: str) -> dict[str, str]:
    blocks: dict[str, str] = {}
    for match in re.finditer(r'variable\s+"([^"]+)"\s*\{', text):
        depth = 1
        index = match.end()
        while index < len(text) and depth:
            depth += text[index] == "{"
            depth -= text[index] == "}"
            index += 1
        blocks[match.group(1)] = text[match.end() : index - 1]
    return blocks


def terraform_variables(path: Path) -> dict[str, str]:
    variables: dict[str, str] = {}
    for name, block in _variable_blocks(Path(path).read_text(encoding="utf-8")).items():
        match = re.search(r"(?m)^\s*type\s*=\s*([^\n]+)", block)
        if match:
            variables[name] = _compact_type(match.group(1))
    return variables


def schema_variables(path: Path) -> dict[str, str]:
    payload = yaml.safe_load(Path(path).read_text(encoding="utf-8")) or {}
    return {name: config["type"] for name, config in (payload.get("variables") or {}).items()}


def validate_schema_parity(schema_path: Path, variables_path: Path) -> list[str]:
    schema = schema_variables(schema_path)
    terraform = terraform_variables(variables_path)
    errors: list[str] = []
    for name, schema_type in schema.items():
        if name not in terraform:
            errors.append(f"schema variable {name} is not declared by Terraform")
            continue
        terraform_type = terraform[name]
        expected = TERRAFORM_TO_SCHEMA_TYPES.get(terraform_type, terraform_type)
        normalized_schema_type = (
            "string"
            if schema_type == "enum" or schema_type == "password" or schema_type.startswith("oci:")
            else "number"
            if schema_type == "integer"
            else schema_type
        )
        if normalized_schema_type != expected:
            errors.append(f"schema variable {name} has type {schema_type}; Terraform type is {terraform_type}")
    return errors
