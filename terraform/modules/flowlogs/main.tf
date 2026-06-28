locals {
  flow_log_targets = {
    for idx, resource_id in var.resource_ids :
    format("%02d", idx) => resource_id
  }
  flow_log_categories = {
    for key, resource_id in local.flow_log_targets :
    key => (
      can(regex("^ocid1\\.subnet\\.", resource_id)) ? "subnet" :
      can(regex("^ocid1\\.vcn\\.", resource_id)) ? "vcn" :
      can(regex("^ocid1\\.vnic\\.", resource_id)) ? "vnic" :
      var.flow_log_category
    )
  }
}

resource "oci_logging_log" "flow" {
  for_each           = local.flow_log_targets
  display_name       = "${var.project_name}-flow-${each.key}"
  log_group_id       = var.log_group_id
  log_type           = "SERVICE"
  is_enabled         = true
  retention_duration = var.log_retention_days
  freeform_tags      = var.freeform_tags
  defined_tags       = var.defined_tags

  configuration {
    compartment_id = var.resource_compartment_id

    source {
      category    = local.flow_log_categories[each.key]
      service     = "flowlogs"
      source_type = "OCISERVICE"
      resource    = each.value
    }
  }
}
