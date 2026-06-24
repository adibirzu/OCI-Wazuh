variable "tenancy_id" { type = string }
variable "compartment_id" { type = string }
variable "project_name" { type = string }
variable "audit_log_resource_id" {
  type        = string
  default     = ""
  description = "Audit resource OCID. Defaults to tenancy_id for tenancy-wide audit ingestion; set to a compartment OCID to scope narrower."
}
variable "audit_log_category" {
  type        = string
  default     = "all"
  description = "OCI Audit log category. Use all for tenancy-wide audit logs; some older compartments may require Audit."
}
variable "log_retention_days" {
  type        = number
  default     = 30
  description = "OCI Logging retention duration in days."
}
variable "freeform_tags" { type = map(string) }
variable "defined_tags" { type = map(string) }
