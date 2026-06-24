output "flow_log_ids" {
  value = [for log in oci_logging_log.flow : log.id]
}

output "flow_log_resource_ids" {
  value = [for log in oci_logging_log.flow : log.configuration[0].source[0].resource]
}
