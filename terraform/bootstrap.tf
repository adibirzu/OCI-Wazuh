data "oci_objectstorage_namespace" "bootstrap" {
  compartment_id = local.effective_compartment_ocid
}

resource "random_id" "bootstrap" {
  byte_length = 4
}

locals {
  bootstrap_namespace = var.object_storage_namespace != "" ? var.object_storage_namespace : data.oci_objectstorage_namespace.bootstrap.namespace
  bootstrap_asset_paths = toset([
    "wazuh/consumer/oci_log_consumer.py",
    "wazuh/decoders/oci-audit-decoders.xml",
    "wazuh/decoders/vcn-flowlog-decoders.xml",
    "wazuh/rules/local_rules.xml",
    "wazuh/rules/oci-audit-rules.xml",
    "wazuh/rules/vcn-flowlog-rules.xml",
    "wazuh/rules/windows-sysmon-rules.xml",
    "dashboards/log-analytics/oci-wazuh-dashboard-queries.json",
    "dashboards/wazuh/oci-wazuh-views.md",
  ])
  generated_bootstrap_files = {
    for relative_path in local.bootstrap_asset_paths :
    relative_path => filebase64("${local.asset_root}/${relative_path}")
  }
  generated_bootstrap_asset_hashes = {
    for relative_path in local.bootstrap_asset_paths :
    relative_path => filesha256("${local.asset_root}/${relative_path}")
  }
  generated_bootstrap_bundle_content = jsonencode({
    files  = local.generated_bootstrap_files
    format = "oci-wazuh-bootstrap-v1"
  })
  generated_bootstrap_manifest_content = jsonencode({
    assets        = local.generated_bootstrap_asset_hashes
    bundle_sha256 = sha256(local.generated_bootstrap_bundle_content)
    format        = "oci-wazuh-bootstrap-manifest-v1"
  })
  bootstrap_bundle_content = fileexists("${path.root}/bootstrap/oci-wazuh-bootstrap.json") ? file(
    "${path.root}/bootstrap/oci-wazuh-bootstrap.json"
  ) : local.generated_bootstrap_bundle_content
  bootstrap_manifest_content = fileexists("${path.root}/bootstrap/manifest.json") ? file(
    "${path.root}/bootstrap/manifest.json"
  ) : local.generated_bootstrap_manifest_content
  bootstrap_bundle_sha256 = sha256(local.bootstrap_bundle_content)
  bootstrap_status_prefix = "status"
}

resource "oci_objectstorage_bucket" "bootstrap" {
  compartment_id = local.effective_compartment_ocid
  namespace      = local.bootstrap_namespace
  name           = "${var.project_name}-bootstrap-${random_id.bootstrap.hex}"
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
  versioning     = "Disabled"
  freeform_tags  = merge(local.common_freeform_tags, { role = "bootstrap" })
  defined_tags   = var.defined_tags
}

resource "oci_objectstorage_object" "bootstrap" {
  namespace    = local.bootstrap_namespace
  bucket       = oci_objectstorage_bucket.bootstrap.name
  object       = "bootstrap/oci-wazuh-bootstrap.json"
  content      = local.bootstrap_bundle_content
  content_type = "application/json"
  metadata = {
    sha256                    = local.bootstrap_bundle_sha256
    project                   = var.project_name
    configuration_fingerprint = local.configuration_fingerprint
  }
}

resource "oci_objectstorage_object" "bootstrap_manifest" {
  namespace    = local.bootstrap_namespace
  bucket       = oci_objectstorage_bucket.bootstrap.name
  object       = "bootstrap/manifest.json"
  content      = local.bootstrap_manifest_content
  content_type = "application/json"
  metadata = {
    project                   = var.project_name
    configuration_fingerprint = local.configuration_fingerprint
  }
}

resource "oci_identity_dynamic_group" "bootstrap_instances" {
  compartment_id = local.effective_tenancy_ocid
  name           = "${var.project_name}-bootstrap-instances"
  description    = "Project instances that read verified bootstrap assets and publish status."
  matching_rule = "ANY {${join(", ", [
    for instance_id in compact(concat(
      [module.wazuh_server.instance_id],
      module.compute.agent_instance_ids,
      module.windows.target_instance_ids,
    )) :
    "instance.id = '${instance_id}'"
  ])}}"
  freeform_tags = local.common_freeform_tags
  defined_tags  = var.defined_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_identity_policy" "bootstrap_objects" {
  compartment_id = local.effective_tenancy_ocid
  name           = "${var.project_name}-bootstrap-objects"
  description    = "Least-scope bootstrap bundle read and status marker write access."
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.bootstrap_instances.name} to read objects in compartment id ${local.effective_compartment_ocid} where all {target.bucket.name='${oci_objectstorage_bucket.bootstrap.name}', any {target.object.name='bootstrap/*', target.object.name='windows/*'}}",
    "Allow dynamic-group ${oci_identity_dynamic_group.bootstrap_instances.name} to manage objects in compartment id ${local.effective_compartment_ocid} where all {target.bucket.name='${oci_objectstorage_bucket.bootstrap.name}', target.object.name='status/*'}",
  ]
  freeform_tags = local.common_freeform_tags
  defined_tags  = var.defined_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}
