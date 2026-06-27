resource "oci_opensearch_opensearch_cluster" "oci_logs" {
  count = var.create_oci_opensearch ? 1 : 0

  compartment_id                     = local.effective_compartment_ocid
  display_name                       = "${var.project_name}-oci-logs-opensearch"
  software_version                   = var.oci_opensearch_software_version
  vcn_id                             = module.network.workload_vcn_id
  vcn_compartment_id                 = module.network.workload_vcn_compartment_id
  subnet_id                          = module.network.workload_subnet_id
  subnet_compartment_id              = module.network.workload_subnet_compartment_id
  master_node_count                  = var.oci_opensearch_master_node_count
  master_node_host_type              = "FLEX"
  master_node_host_ocpu_count        = var.oci_opensearch_master_node_ocpus
  master_node_host_memory_gb         = var.oci_opensearch_master_node_memory_gb
  data_node_count                    = var.oci_opensearch_data_node_count
  data_node_host_type                = "FLEX"
  data_node_host_ocpu_count          = var.oci_opensearch_data_node_ocpus
  data_node_host_memory_gb           = var.oci_opensearch_data_node_memory_gb
  data_node_storage_gb               = var.oci_opensearch_data_node_storage_gb
  opendashboard_node_count           = var.oci_opensearch_dashboard_node_count
  opendashboard_node_host_ocpu_count = var.oci_opensearch_dashboard_node_ocpus
  opendashboard_node_host_memory_gb  = var.oci_opensearch_dashboard_node_memory_gb
  security_mode                      = var.oci_opensearch_security_mode
  security_master_user_name          = var.oci_opensearch_master_user_name
  security_master_user_password_hash = var.oci_opensearch_master_password_hash == "" ? null : var.oci_opensearch_master_password_hash
  freeform_tags                      = merge(local.common_freeform_tags, { role = "oci-opensearch-logs" })
  defined_tags                       = var.defined_tags
}
