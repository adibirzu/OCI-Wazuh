output "selected_mode" {
  value = local.selected_mode
}

output "service_connector_id" {
  value = try(oci_sch_service_connector.logs_to_streaming[0].id, try(oci_sch_service_connector.logs_to_object_storage[0].id, null))
}

output "object_storage_namespace" {
  value = try(data.oci_objectstorage_namespace.this[0].namespace, null)
}

output "object_storage_bucket" {
  value = try(oci_objectstorage_bucket.oci_logs[0].name, null)
}

output "object_storage_prefix" {
  value = local.object_enabled ? "oci-logs/" : null
}
