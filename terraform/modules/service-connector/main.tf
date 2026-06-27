locals {
  selected_mode   = var.ingestion_mode
  enabled_log_ids = distinct(compact(var.log_ids))
  enabled_log_sources = length(var.log_sources) > 0 ? var.log_sources : [
    for log_id in local.enabled_log_ids : {
      compartment_id = var.compartment_id
      log_group_id   = var.log_group_id
      log_id         = log_id
    }
  ]
  streaming_enabled = var.ingestion_mode == "streaming"
  # direct_api uses the Audit API directly and Object Storage for Flow Logs.
  object_enabled = contains(["object_storage", "direct_api"], var.ingestion_mode)
  effective_object_storage_namespace = var.object_storage_namespace != "" ? var.object_storage_namespace : try(
    data.oci_objectstorage_namespace.this[0].namespace,
    "",
  )
}

data "oci_objectstorage_namespace" "this" {
  count          = local.object_enabled && var.object_storage_namespace == "" ? 1 : 0
  compartment_id = var.compartment_id
}

resource "oci_objectstorage_bucket" "oci_logs" {
  count          = local.object_enabled ? 1 : 0
  compartment_id = var.compartment_id
  namespace      = local.effective_object_storage_namespace
  name           = "${var.project_name}-oci-log-batches"
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
  freeform_tags  = var.freeform_tags
  defined_tags   = var.defined_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_identity_policy" "object_target" {
  count          = local.object_enabled ? 1 : 0
  compartment_id = var.tenancy_id
  name           = "${var.project_name}-sch-object-target"
  description    = "Allow Service Connector Hub to write only to the project Flow Log bucket."
  statements = [
    "Allow any-user to manage objects in compartment id ${var.compartment_id} where all {request.principal.type='serviceconnector', target.bucket.name='${oci_objectstorage_bucket.oci_logs[0].name}'}",
  ]
  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_sch_service_connector" "logs_to_streaming" {
  count          = local.streaming_enabled ? 1 : 0
  compartment_id = var.compartment_id
  display_name   = "${var.project_name}-oci-logs-to-streaming"
  description    = "Routes OCI VCN Flow Logs to OCI Streaming for Wazuh ingestion."
  freeform_tags  = var.freeform_tags
  defined_tags   = var.defined_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }

  source {
    kind = "logging"

    dynamic "log_sources" {
      for_each = { for idx, source in local.enabled_log_sources : tostring(idx) => source }
      content {
        compartment_id = log_sources.value.compartment_id
        log_group_id   = log_sources.value.log_group_id
        log_id         = log_sources.value.log_id
      }
    }
  }

  target {
    kind      = "streaming"
    stream_id = var.stream_id
  }
}

resource "oci_sch_service_connector" "logs_to_object_storage" {
  count          = local.object_enabled ? 1 : 0
  compartment_id = var.compartment_id
  display_name   = "${var.project_name}-oci-logs-to-object-storage"
  description    = "Routes OCI VCN Flow Logs to Object Storage for Wazuh polling fallback."
  freeform_tags  = var.freeform_tags
  defined_tags   = var.defined_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }

  source {
    kind = "logging"

    dynamic "log_sources" {
      for_each = { for idx, source in local.enabled_log_sources : tostring(idx) => source }
      content {
        compartment_id = log_sources.value.compartment_id
        log_group_id   = log_sources.value.log_group_id
        log_id         = log_sources.value.log_id
      }
    }
  }

  target {
    kind               = "objectStorage"
    namespace          = local.effective_object_storage_namespace
    bucket             = oci_objectstorage_bucket.oci_logs[0].name
    object_name_prefix = "oci-logs/"
  }

  depends_on = [oci_identity_policy.object_target]
}
