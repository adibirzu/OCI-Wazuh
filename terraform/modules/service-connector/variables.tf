variable "tenancy_id" { type = string }
variable "compartment_id" { type = string }
variable "project_name" { type = string }
variable "ingestion_mode" { type = string }
variable "object_storage_namespace" {
  type      = string
  default   = ""
  sensitive = true
}
variable "stream_id" { type = string }
variable "log_group_id" { type = string }
variable "log_ids" { type = list(string) }
variable "log_sources" {
  type = list(object({
    compartment_id = string
    log_group_id   = string
    log_id         = string
  }))
  default     = []
  description = "Existing or managed OCI Logging sources to route. Each entry must include the source log group OCID and log OCID."
}
variable "freeform_tags" { type = map(string) }
variable "defined_tags" { type = map(string) }
