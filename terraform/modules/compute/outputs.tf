output "bastion_public_ip" {
  value = oci_core_instance.bastion.public_ip
}

output "bastion_private_ip" {
  value = oci_core_instance.bastion.private_ip
}

output "ol9_agent_private_ip" {
  value = oci_core_instance.ol9_agent.private_ip
}

output "ol9_agent_public_ip" {
  value = oci_core_instance.ol9_agent.public_ip
}

output "ubuntu_agent_private_ip" {
  value = oci_core_instance.ubuntu_agent.private_ip
}

output "ubuntu_agent_public_ip" {
  value = oci_core_instance.ubuntu_agent.public_ip
}

output "instance_ids" {
  value = [
    oci_core_instance.bastion.id,
    oci_core_instance.ol9_agent.id,
    oci_core_instance.ubuntu_agent.id,
  ]
}

output "agent_instance_ids" {
  value = [
    oci_core_instance.ol9_agent.id,
    oci_core_instance.ubuntu_agent.id,
  ]
}
