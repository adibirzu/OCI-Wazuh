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
  object_enabled    = var.ingestion_mode == "object_storage"
}

data "oci_objectstorage_namespace" "this" {
  count          = local.object_enabled ? 1 : 0
  compartment_id = var.compartment_id
}

resource "oci_objectstorage_bucket" "oci_logs" {
  count          = local.object_enabled ? 1 : 0
  compartment_id = var.compartment_id
  namespace      = data.oci_objectstorage_namespace.this[0].namespace
  name           = "${var.project_name}-oci-log-batches"
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
  freeform_tags  = var.freeform_tags
  defined_tags   = var.defined_tags

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
    namespace          = data.oci_objectstorage_namespace.this[0].namespace
    bucket             = oci_objectstorage_bucket.oci_logs[0].name
    object_name_prefix = "oci-logs/"
  }
}
