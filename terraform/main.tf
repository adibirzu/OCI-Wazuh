module "network" {
  source                      = "./modules/network"
  mode                        = var.network_mode
  compartment_id              = local.effective_compartment_ocid
  project_name                = var.project_name
  operator_cidr               = var.operator_cidr
  vcn_cidr                    = var.vcn_cidr
  bastion_subnet_cidr         = var.bastion_subnet_cidr
  workload_subnet_cidr        = var.workload_subnet_cidr
  existing_bastion_subnet_id  = var.bastion_subnet_id
  existing_workload_subnet_id = var.agent_subnet_id
  goad_agent_cidrs            = var.goad_agent_cidrs
  freeform_tags               = local.common_freeform_tags
  defined_tags                = var.defined_tags

  depends_on = [terraform_data.input_contract]
}

module "streaming" {
  count          = local.effective_ingestion_mode == "streaming" ? 1 : 0
  source         = "./modules/streaming"
  compartment_id = local.effective_compartment_ocid
  project_name   = var.project_name
  freeform_tags  = local.common_freeform_tags
  defined_tags   = var.defined_tags
}

module "logging_audit" {
  source                = "./modules/logging-audit"
  tenancy_id            = local.effective_tenancy_ocid
  compartment_id        = local.effective_compartment_ocid
  project_name          = var.project_name
  audit_log_resource_id = var.audit_log_resource_id
  audit_log_category    = var.audit_log_category
  log_retention_days    = var.oci_log_retention_days
  freeform_tags         = local.common_freeform_tags
  defined_tags          = var.defined_tags
}

locals {
  flow_log_resource_ids         = length(var.flow_log_resource_ids) > 0 ? var.flow_log_resource_ids : [module.network.workload_subnet_id]
  managed_flow_log_resource_ids = length(var.existing_flow_logs) > 0 ? [] : local.flow_log_resource_ids
  managed_flow_log_sources = [
    for log_id in module.flowlogs.flow_log_ids : {
      compartment_id = local.effective_compartment_ocid
      log_group_id   = module.logging_audit.log_group_id
      log_id         = log_id
    }
  ]
  oci_log_sources = length(var.existing_flow_logs) > 0 ? var.existing_flow_logs : local.managed_flow_log_sources
  oci_log_ids     = [for source in local.oci_log_sources : source.log_id]
}

module "flowlogs" {
  source                  = "./modules/flowlogs"
  project_name            = var.project_name
  log_group_id            = module.logging_audit.log_group_id
  resource_ids            = local.managed_flow_log_resource_ids
  resource_compartment_id = var.flow_log_resource_compartment_id != "" ? var.flow_log_resource_compartment_id : module.network.workload_subnet_compartment_id
  log_retention_days      = var.oci_log_retention_days
  flow_log_category       = var.flow_log_category
  freeform_tags           = local.common_freeform_tags
  defined_tags            = var.defined_tags
}

module "service_connector" {
  source                   = "./modules/service-connector"
  tenancy_id               = local.effective_tenancy_ocid
  compartment_id           = local.effective_compartment_ocid
  project_name             = var.project_name
  ingestion_mode           = local.effective_ingestion_mode
  stream_id                = try(module.streaming[0].stream_id, "")
  log_group_id             = module.logging_audit.log_group_id
  log_ids                  = local.oci_log_ids
  log_sources              = local.oci_log_sources
  object_storage_namespace = var.object_storage_namespace
  freeform_tags            = local.common_freeform_tags
  defined_tags             = var.defined_tags

  depends_on = [
    oci_identity_policy.sch_log_source,
    oci_identity_policy.sch_stream_target,
  ]
}

module "wazuh_server" {
  source                    = "./modules/wazuh-server"
  compartment_id            = local.effective_compartment_ocid
  project_name              = var.project_name
  availability_domain       = local.availability_domain
  image_id                  = local.ubuntu2404_image_id
  shape                     = var.wazuh_shape
  subnet_id                 = module.network.workload_subnet_id
  wazuh_nsg_ids             = [module.network.wazuh_nsg_id]
  ssh_public_key            = local.ssh_public_key
  wazuh_version             = var.wazuh_version
  wazuh_installer_sha256    = var.wazuh_installer_sha256
  bootstrap_namespace       = local.bootstrap_namespace
  bootstrap_bucket          = oci_objectstorage_bucket.bootstrap.name
  bootstrap_bundle_object   = oci_objectstorage_object.bootstrap.object
  bootstrap_manifest_object = oci_objectstorage_object.bootstrap_manifest.object
  bootstrap_bundle_sha256   = local.bootstrap_bundle_sha256
  bootstrap_status_prefix   = local.bootstrap_status_prefix
  region                    = var.region
  ingestion_mode            = local.effective_ingestion_mode
  stream_id                 = try(module.streaming[0].stream_id, "")
  stream_endpoint           = try(module.streaming[0].messages_endpoint, "")
  object_namespace          = module.service_connector.object_storage_namespace == null ? "" : module.service_connector.object_storage_namespace
  object_bucket             = module.service_connector.object_storage_bucket == null ? "" : module.service_connector.object_storage_bucket
  object_prefix             = module.service_connector.object_storage_prefix == null ? "" : module.service_connector.object_storage_prefix
  audit_compartment_id      = var.audit_log_resource_id != "" ? var.audit_log_resource_id : local.effective_tenancy_ocid
  freeform_tags             = local.common_freeform_tags
  defined_tags              = var.defined_tags
}

module "compute" {
  source                      = "./modules/compute"
  compartment_id              = local.effective_compartment_ocid
  project_name                = var.project_name
  availability_domain         = local.availability_domain
  ol9_image_id                = local.ol9_image_id
  ubuntu2404_image_id         = local.ubuntu2404_image_id
  bastion_shape               = var.bastion_shape
  agent_shape                 = var.linux_agent_shape
  bastion_subnet_id           = module.network.bastion_subnet_id
  agent_subnet_id             = module.network.workload_subnet_id
  bastion_nsg_ids             = [module.network.bastion_nsg_id]
  agent_nsg_ids               = [module.network.agent_nsg_id]
  ssh_public_key              = local.ssh_public_key
  wazuh_manager_ip            = module.wazuh_server.private_ip
  wazuh_version               = var.wazuh_version
  wazuh_repository_key_sha256 = var.wazuh_repository_key_sha256
  bootstrap_namespace         = local.bootstrap_namespace
  bootstrap_bucket            = oci_objectstorage_bucket.bootstrap.name
  bootstrap_status_prefix     = local.bootstrap_status_prefix
  region                      = var.region
  freeform_tags               = local.common_freeform_tags
  defined_tags                = var.defined_tags
}
