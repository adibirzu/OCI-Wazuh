variable "mode" {
  type = string
}
variable "compartment_id" {
  type = string
}
variable "project_name" {
  type = string
}
variable "operator_cidr" {
  type = string
}
variable "vcn_cidr" {
  type = string
}
variable "bastion_subnet_cidr" {
  type = string
}
variable "workload_subnet_cidr" {
  type = string
}
variable "existing_bastion_subnet_id" {
  type = string
}
variable "existing_workload_subnet_id" {
  type = string
}
variable "goad_agent_cidrs" {
  type    = list(string)
  default = []
}
variable "freeform_tags" {
  type = map(string)
}
variable "defined_tags" {
  type = map(string)
}
