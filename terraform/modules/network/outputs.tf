output "bastion_subnet_id" {
  value = local.bastion_subnet_id
}
output "workload_subnet_id" {
  value = local.workload_subnet_id
}
output "bastion_subnet_cidr" {
  value = local.bastion_cidr
}
output "workload_subnet_cidr" {
  value = local.workload_cidr
}
output "bastion_vcn_id" {
  value = local.bastion_vcn_id
}
output "workload_vcn_id" {
  value = local.workload_vcn_id
}
output "workload_vcn_compartment_id" {
  value = local.workload_vcn_compartment_id
}
output "workload_subnet_compartment_id" {
  value = local.workload_subnet_compartment_id
}
output "bastion_nsg_id" {
  value = oci_core_network_security_group.bastion.id
}
output "wazuh_nsg_id" {
  value = oci_core_network_security_group.wazuh.id
}
output "agent_nsg_id" {
  value = oci_core_network_security_group.agents.id
}
output "vcn_id" {
  value = try(oci_core_vcn.this[0].id, null)
}
