locals {
  oci_log_source_compartment_ids = distinct([for source in local.oci_log_sources : source.compartment_id])
  sch_log_source_policy_scope_ids = {
    for index, compartment_id in local.oci_log_source_compartment_ids : tostring(index) => compartment_id
  }
  audit_read_statement = var.audit_log_resource_id == "" || startswith(var.audit_log_resource_id, "ocid1.tenancy.") ? (
    "Allow dynamic-group ${oci_identity_dynamic_group.wazuh_consumer.name} to read audit-events in tenancy"
    ) : (
    "Allow dynamic-group ${oci_identity_dynamic_group.wazuh_consumer.name} to read audit-events in compartment id ${var.audit_log_resource_id}"
  )
}

resource "oci_identity_dynamic_group" "wazuh_consumer" {
  compartment_id = local.effective_tenancy_ocid
  name           = "${var.project_name}-wazuh-consumer"
  description    = "Wazuh OCI log consumer instance principal."
  matching_rule  = "instance.id = '${module.wazuh_server.instance_id}'"
  freeform_tags  = local.common_freeform_tags
  defined_tags   = var.defined_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_identity_policy" "wazuh_consumer" {
  compartment_id = local.effective_tenancy_ocid
  name           = "${var.project_name}-wazuh-consumer"
  description    = "Allow Wazuh to consume only the selected OCI log transports and Audit API."
  statements = compact([
    "Allow dynamic-group ${oci_identity_dynamic_group.wazuh_consumer.name} to inspect compartments in tenancy",
    local.audit_read_statement,
    local.effective_ingestion_mode == "streaming" ? "Allow dynamic-group ${oci_identity_dynamic_group.wazuh_consumer.name} to use stream-pull in compartment id ${local.effective_compartment_ocid}" : "",
    local.effective_ingestion_mode == "streaming" ? "Allow dynamic-group ${oci_identity_dynamic_group.wazuh_consumer.name} to inspect streams in compartment id ${local.effective_compartment_ocid}" : "",
    contains(["object_storage", "direct_api"], local.effective_ingestion_mode) ? "Allow dynamic-group ${oci_identity_dynamic_group.wazuh_consumer.name} to read objects in compartment id ${local.effective_compartment_ocid} where target.bucket.name='${module.service_connector.object_storage_bucket}'" : "",
  ])
  freeform_tags = local.common_freeform_tags
  defined_tags  = var.defined_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_identity_policy" "sch_log_source" {
  for_each       = toset(nonsensitive(keys(sensitive(local.sch_log_source_policy_scope_ids))))
  compartment_id = local.effective_tenancy_ocid
  name           = "${var.project_name}-sch-log-source-${each.key}"
  description    = "Allow Service Connector Hub to read selected OCI Flow Logs."
  statements = [
    "Allow any-user to read log-content in compartment id ${local.sch_log_source_policy_scope_ids[each.key]} where request.principal.type='serviceconnector'",
  ]
  freeform_tags = local.common_freeform_tags
  defined_tags  = var.defined_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_identity_policy" "sch_stream_target" {
  count          = local.effective_ingestion_mode == "streaming" ? 1 : 0
  compartment_id = local.effective_tenancy_ocid
  name           = "${var.project_name}-sch-stream-target"
  description    = "Allow Service Connector Hub to publish selected Flow Logs to the project stream."
  statements = [
    "Allow any-user to use stream-push in compartment id ${local.effective_compartment_ocid} where request.principal.type='serviceconnector'",
  ]
  freeform_tags = local.common_freeform_tags
  defined_tags  = var.defined_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}
