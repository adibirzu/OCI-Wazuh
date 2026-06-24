resource "oci_logging_log_group" "oci" {
  compartment_id = var.compartment_id
  display_name   = "${var.project_name}-oci-service-logs"
  description    = "OCI service logs for the Wazuh detection lab. Audit is ingested through the OCI Audit API."
  freeform_tags  = var.freeform_tags
  defined_tags   = var.defined_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}
