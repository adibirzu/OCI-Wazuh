output "project_name" {
  value       = var.project_name
  description = "Project name and mandatory free-form tag value."
}

output "effective_modes" {
  value = {
    ingestion_mode     = local.effective_ingestion_mode
    log_analytics      = local.effective_log_analytics
    managed_opensearch = var.create_oci_opensearch
    network_mode       = var.network_mode
    reuse_goad_action  = local.effective_reuse_goad_action
    windows_mode       = local.effective_windows_mode
  }
  description = "Normalized modes after applying one-release compatibility aliases."
}

output "bastion_public_ip" {
  value       = module.compute.bastion_public_ip
  description = "Bastion public IP."
  sensitive   = true
}

output "bastion_private_ip" {
  value       = module.compute.bastion_private_ip
  description = "Bastion private IP."
  sensitive   = true
}

output "wazuh_private_ip" {
  value       = module.wazuh_server.private_ip
  description = "Wazuh server private IP."
  sensitive   = true
}

output "wazuh_public_ip" {
  value       = null
  description = "Compatibility output. M11 never assigns Wazuh a public IP."
}

output "wazuh_dashboard_tunnel_command" {
  value       = "ssh -i ${var.ssh_private_key_path} -L 8443:${module.wazuh_server.private_ip}:443 ubuntu@${module.compute.bastion_public_ip}"
  description = "Local SSH tunnel command for https://127.0.0.1:8443."
  sensitive   = true
}

output "ol9_agent_private_ip" {
  value     = module.compute.ol9_agent_private_ip
  sensitive = true
}

output "ol9_agent_public_ip" {
  value       = null
  description = "Compatibility output. M11 Linux agents are private."
}

output "ubuntu_agent_private_ip" {
  value     = module.compute.ubuntu_agent_private_ip
  sensitive = true
}

output "ubuntu_agent_public_ip" {
  value       = null
  description = "Compatibility output. M11 Linux agents are private."
}

output "windows_target_names" {
  value       = module.windows.target_names
  description = "Standalone or GOAD Windows targets selected by windows_mode."
}

output "goad_upstream_commit" {
  value       = module.windows.goad_upstream_commit
  description = "Pinned GOADv3 upstream commit used by the five-host adaptation."
}

output "oci_log_group_id" {
  value       = module.logging_audit.log_group_id
  description = "OCI Logging group used for managed Flow Logs."
  sensitive   = true
}

output "oci_audit_log_id" {
  value       = module.logging_audit.audit_log_id
  description = "Compatibility output; Audit ingestion uses the real OCI Audit API."
  sensitive   = true
}

output "oci_flow_log_ids" {
  value       = local.oci_log_ids
  description = "Managed or reused Flow Log OCIDs."
  sensitive   = true
}

output "oci_log_stream_id" {
  value       = try(module.streaming[0].stream_id, null)
  description = "Streaming OCID when streaming mode is selected."
  sensitive   = true
}

output "oci_log_stream_pool_id" {
  value       = try(module.streaming[0].stream_pool_id, null)
  description = "Stream pool OCID when streaming mode is selected."
  sensitive   = true
}

output "oci_log_stream_messages_endpoint" {
  value       = try(module.streaming[0].messages_endpoint, null)
  description = "Private consumer endpoint for the project stream."
  sensitive   = true
}

output "oci_log_service_connector_id" {
  value       = module.service_connector.service_connector_id
  description = "Flow Log Service Connector OCID."
  sensitive   = true
}

output "oci_log_object_storage_namespace" {
  value       = module.service_connector.object_storage_namespace
  description = "Object Storage namespace for object_storage or direct_api Flow transport."
  sensitive   = true
}

output "oci_log_object_storage_bucket" {
  value       = module.service_connector.object_storage_bucket
  description = "Private Flow Log batch bucket name."
  sensitive   = true
}

output "oci_log_object_storage_prefix" {
  value       = module.service_connector.object_storage_prefix
  description = "Flow Log object prefix."
}

output "oci_log_ingestion_mode" {
  value       = local.effective_ingestion_mode
  description = "Normalized OCI log ingestion mode."
}

output "oci_opensearch_cluster_id" {
  value       = try(oci_opensearch_opensearch_cluster.oci_logs[0].id, null)
  description = "Optional managed OpenSearch cluster OCID."
  sensitive   = true
}

output "oci_opensearch_url" {
  value       = try("https://${oci_opensearch_opensearch_cluster.oci_logs[0].opensearch_fqdn}:9200", null)
  description = "Optional private OpenSearch API URL."
  sensitive   = true
}

output "oci_opensearch_dashboard_url" {
  value       = try("https://${oci_opensearch_opensearch_cluster.oci_logs[0].opendashboard_fqdn}:5601", null)
  description = "Optional private OpenSearch Dashboard URL."
  sensitive   = true
}

output "dashboard_identifiers" {
  value = {
    log_analytics_query_pack = "oci-wazuh-correlation"
    opensearch               = "oci-logs-overview"
    wazuh_data_views         = ["wazuh-alerts-*", "oci-audit-*", "oci-flow-*"]
  }
  description = "Stable dashboard and data-view identifiers used by idempotent imports."
}

output "bootstrap_status" {
  value = {
    bundle_sha256          = local.bootstrap_bundle_sha256
    expected_linux_markers = 3
    expected_windows       = nonsensitive(length(module.windows.target_instance_ids))
    status_prefix          = local.bootstrap_status_prefix
  }
  description = "Expected Object Storage bootstrap marker contract."
}

output "bootstrap_object_storage_namespace" {
  value       = local.bootstrap_namespace
  description = "Runtime-only namespace used by live validation scripts."
  sensitive   = true
}

output "bootstrap_object_storage_bucket" {
  value       = oci_objectstorage_bucket.bootstrap.name
  description = "Runtime-only private bootstrap/status bucket used by live validation scripts."
  sensitive   = true
}

output "log_analytics_namespace" {
  value       = local.effective_log_analytics ? local.log_analytics_namespace : null
  description = "Runtime-only Log Analytics namespace used by live freshness validation."
  sensitive   = true
}

output "m11_validation_status" {
  value = {
    live_gate_required   = true
    public_wazuh_allowed = false
    required_checks = [
      "wazuh-api",
      "linux-agents",
      "fim",
      "windows-selection",
      "real-oci-audit",
      "real-vcn-flow",
      "opensearch-views",
      "dashboards",
      "log-analytics-freshness",
      "zero-residual-resources",
    ]
    reuse_cleanup_required = local.effective_windows_mode == "reuse_goad"
    state                  = "pending-live-validation"
  }
  description = "M11 live acceptance contract; it becomes green only through the unified live gate."
}
