output "bastion_public_ip" {
  value       = module.compute.bastion_public_ip
  description = "Bastion public IP."
}

output "wazuh_private_ip" {
  value       = module.wazuh_server.private_ip
  description = "Wazuh server private IP."
}

output "wazuh_public_ip" {
  value       = module.wazuh_server.public_ip
  description = "Wazuh server public IP when workload_assign_public_ip is enabled for controlled development fallback."
}

output "wazuh_dashboard_tunnel_command" {
  value       = "ssh -i ${var.ssh_private_key_path} -L 8443:${module.wazuh_server.private_ip}:443 ubuntu@${module.compute.bastion_public_ip}"
  description = "SSH tunnel command template for the Wazuh dashboard."
}

output "ol9_agent_private_ip" {
  value = module.compute.ol9_agent_private_ip
}

output "ol9_agent_public_ip" {
  value       = module.compute.ol9_agent_public_ip
  description = "OL9 agent public IP when workload_assign_public_ip is enabled for controlled development fallback."
}

output "ubuntu_agent_private_ip" {
  value = module.compute.ubuntu_agent_private_ip
}

output "ubuntu_agent_public_ip" {
  value       = module.compute.ubuntu_agent_public_ip
  description = "Ubuntu agent public IP when workload_assign_public_ip is enabled for controlled development fallback."
}
