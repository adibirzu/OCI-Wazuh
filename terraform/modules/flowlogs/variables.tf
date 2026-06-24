variable "project_name" { type = string }
variable "log_group_id" { type = string }
variable "resource_ids" {
  type        = list(string)
  description = "Subnet or VNIC OCIDs to enable VCN Flow Logs for."
}
variable "log_retention_days" {
  type    = number
  default = 30
}
variable "flow_log_category" {
  type        = string
  default     = "subnet"
  description = "Fallback OCI Flow Logs category. Subnet, VCN, and VNIC OCIDs are auto-mapped to all/vcn/vnic."
}
variable "freeform_tags" { type = map(string) }
variable "defined_tags" { type = map(string) }
