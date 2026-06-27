locals {
  effective_tenancy_ocid      = var.tenancy_ocid != "" ? var.tenancy_ocid : var.tenancy_id
  effective_compartment_ocid  = var.compartment_ocid != "" ? var.compartment_ocid : var.compartment_id
  effective_ingestion_mode    = var.ingestion_mode == "log_analytics_bridge" ? "direct_api" : var.ingestion_mode
  effective_windows_mode      = var.windows_mode == "auto" ? "skip" : var.windows_mode
  effective_reuse_goad_action = local.effective_windows_mode == "reuse_goad" ? var.reuse_goad_action : "install"
  effective_log_analytics     = var.enable_log_analytics_bridge || var.ingestion_mode == "log_analytics_bridge"
  configuration_fingerprint = sha256(jsonencode({
    region                   = var.region
    project_name             = var.project_name
    network_mode             = var.network_mode
    effective_ingestion_mode = local.effective_ingestion_mode
    effective_windows_mode   = local.effective_windows_mode
    log_analytics             = local.effective_log_analytics
    wazuh_version             = var.wazuh_version
    bastion_shape             = var.bastion_shape
    wazuh_shape               = var.wazuh_shape
    linux_agent_shape         = var.linux_agent_shape
    windows_shape             = var.windows_shape
    vcn_cidr                  = var.vcn_cidr
    bastion_subnet_cidr       = var.bastion_subnet_cidr
    workload_subnet_cidr      = var.workload_subnet_cidr
  }))
  common_freeform_tags = {
    project                   = var.project_name
    component                 = "wazuh-detection-lab"
    configuration_fingerprint = local.configuration_fingerprint
  }
  ssh_public_key = var.ssh_public_key != "" ? trimspace(var.ssh_public_key) : try(trimspace(file(pathexpand(var.ssh_public_key_path))), "")
  asset_root     = fileexists("${path.root}/wazuh/rules/local_rules.xml") ? path.root : "${path.root}/.."
}
