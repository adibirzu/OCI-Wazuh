output "bastion_public_ip" {
  value       = module.compute.bastion_public_ip
  description = "Bastion public IP."
}

output "project_name" {
  value       = var.project_name
  description = "Project name used for resource naming."
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

output "oci_log_group_id" {
  value       = module.logging_audit.log_group_id
  description = "OCI Logging log group used for VCN Flow logs."
}

output "oci_audit_log_id" {
  value       = module.logging_audit.audit_log_id
  description = "Null for the default real Audit API path. OCI Audit is ingested directly by the Wazuh consumer."
}

output "oci_flow_log_ids" {
  value       = local.oci_log_ids
  description = "VCN Flow service log OCIDs."
}

output "oci_log_stream_id" {
  value       = try(module.streaming[0].stream_id, null)
  description = "OCI Streaming stream used by the Wazuh consumer."
}

output "oci_log_stream_pool_id" {
  value       = try(module.streaming[0].stream_pool_id, null)
  description = "OCI Streaming stream pool used by the Wazuh consumer."
}

output "oci_log_stream_messages_endpoint" {
  value       = try(module.streaming[0].messages_endpoint, null)
  description = "OCI Streaming messages endpoint for the Wazuh consumer."
}

output "oci_log_service_connector_id" {
  value       = module.service_connector.service_connector_id
  description = "Service Connector routing OCI logs to the selected ingestion target."
}

output "oci_log_object_storage_namespace" {
  value       = module.service_connector.object_storage_namespace
  description = "Object Storage namespace used when ingestion_mode is object_storage."
}

output "oci_log_object_storage_bucket" {
  value       = module.service_connector.object_storage_bucket
  description = "Object Storage bucket used when ingestion_mode is object_storage."
}

output "oci_log_object_storage_prefix" {
  value       = module.service_connector.object_storage_prefix
  description = "Object Storage object prefix used when ingestion_mode is object_storage."
}

output "oci_log_ingestion_mode" {
  value       = module.service_connector.selected_mode
  description = "Selected OCI log ingestion mode."
}

output "oci_opensearch_cluster_id" {
  value       = try(oci_opensearch_opensearch_cluster.oci_logs[0].id, null)
  description = "Optional OCI OpenSearch cluster OCID when create_oci_opensearch is true."
}

output "oci_opensearch_url" {
  value       = try("https://${oci_opensearch_opensearch_cluster.oci_logs[0].opensearch_fqdn}:9200", null)
  description = "Optional OCI OpenSearch API URL for OCI Audit and VCN Flow dedicated indices."
}

output "oci_opensearch_dashboard_url" {
  value       = try("https://${oci_opensearch_opensearch_cluster.oci_logs[0].opendashboard_fqdn}:5601", null)
  description = "Optional OCI OpenSearch Dashboard URL."
}
