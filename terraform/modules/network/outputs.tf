output "vcn_id" {
  value = oci_core_vcn.this.id
}

output "public_subnet_id" {
  value = oci_core_subnet.public.id
}

output "private_subnet_id" {
  value = oci_core_subnet.private.id
}

output "bastion_public_ip" {
  value = null
}

output "bastion_nsg_id" {
  value = oci_core_network_security_group.bastion.id
}

output "wazuh_nsg_id" {
  value = oci_core_network_security_group.wazuh.id
}

output "agent_nsg_id" {
  value = oci_core_network_security_group.agent.id
}
