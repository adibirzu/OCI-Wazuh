output "log_group_id" {
  value = oci_logging_log_group.oci.id
}

output "audit_log_id" {
  value = null
}
