variable "mode" { type = string }
variable "action" { type = string }
variable "compartment_id" { type = string }
variable "tenancy_id" { type = string }
variable "goad_compartment_id" { type = string }
variable "reused_instance_ocids" { type = map(string) }
variable "goad_vault_secret_id" {
  type      = string
  sensitive = true
}
variable "project_name" { type = string }
variable "availability_domain" { type = string }
variable "windows_image_id" { type = string }
variable "runner_image_id" { type = string }
variable "windows_shape" { type = string }
variable "runner_shape" { type = string }
variable "subnet_id" { type = string }
variable "nsg_ids" { type = list(string) }
variable "ssh_public_key" { type = string }
variable "bootstrap_namespace" { type = string }
variable "bootstrap_bucket" { type = string }
variable "install_object_name" { type = string }
variable "cleanup_object_name" { type = string }
variable "region" { type = string }
variable "freeform_tags" { type = map(string) }
variable "defined_tags" { type = map(string) }
