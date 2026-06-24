locals {
  common_freeform_tags = {
    project   = var.project_name
    component = "wazuh-detection-lab"
  }
  flow_log_resource_ids         = length(var.flow_log_resource_ids) > 0 ? var.flow_log_resource_ids : [var.agent_subnet_id]
  managed_flow_log_resource_ids = length(var.existing_flow_logs) > 0 ? [] : local.flow_log_resource_ids
  managed_flow_log_sources = [
    for log_id in module.flowlogs.flow_log_ids : {
      compartment_id = var.compartment_id
      log_group_id   = module.logging_audit.log_group_id
      log_id         = log_id
    }
  ]
  oci_log_sources                 = length(var.existing_flow_logs) > 0 ? var.existing_flow_logs : local.managed_flow_log_sources
  oci_log_ids                     = [for source in local.oci_log_sources : source.log_id]
  oci_log_source_compartment_ids  = distinct([for source in local.oci_log_sources : source.compartment_id])
  sch_log_source_policy_scope_ids = { for idx, compartment_id in local.oci_log_source_compartment_ids : tostring(idx) => compartment_id }
  stream_id                       = var.ingestion_mode == "streaming" ? module.streaming[0].stream_id : ""
}

data "oci_core_subnet" "bastion" {
  subnet_id = var.bastion_subnet_id
}

data "oci_core_subnet" "workload" {
  subnet_id = var.agent_subnet_id
}

resource "oci_core_network_security_group" "wazuh" {
  compartment_id = data.oci_core_subnet.workload.compartment_id
  vcn_id         = data.oci_core_subnet.workload.vcn_id
  display_name   = "${var.project_name}-wazuh-nsg"
  freeform_tags  = merge(local.common_freeform_tags, { role = "wazuh-nsg" })
  defined_tags   = var.defined_tags
}

resource "oci_core_network_security_group" "agents" {
  compartment_id = data.oci_core_subnet.workload.compartment_id
  vcn_id         = data.oci_core_subnet.workload.vcn_id
  display_name   = "${var.project_name}-agents-nsg"
  freeform_tags  = merge(local.common_freeform_tags, { role = "agents-nsg" })
  defined_tags   = var.defined_tags
}

resource "oci_core_network_security_group" "bastion" {
  compartment_id = data.oci_core_subnet.bastion.compartment_id
  vcn_id         = data.oci_core_subnet.bastion.vcn_id
  display_name   = "${var.project_name}-bastion-nsg"
  freeform_tags  = merge(local.common_freeform_tags, { role = "bastion-nsg" })
  defined_tags   = var.defined_tags
}

resource "oci_core_network_security_group_security_rule" "bastion_ssh_from_operator" {
  network_security_group_id = oci_core_network_security_group.bastion.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.operator_cidr
  source_type               = "CIDR_BLOCK"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_network_security_group_security_rule" "bastion_egress" {
  network_security_group_id = oci_core_network_security_group.bastion.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}

resource "oci_core_network_security_group_security_rule" "wazuh_ssh_from_bastion" {
  network_security_group_id = oci_core_network_security_group.wazuh.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = data.oci_core_subnet.bastion.cidr_block
  source_type               = "CIDR_BLOCK"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_network_security_group_security_rule" "wazuh_dashboard_from_bastion" {
  network_security_group_id = oci_core_network_security_group.wazuh.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = data.oci_core_subnet.bastion.cidr_block
  source_type               = "CIDR_BLOCK"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "wazuh_agent_enrollment" {
  for_each                  = toset(["1514", "1515"])
  network_security_group_id = oci_core_network_security_group.wazuh.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = data.oci_core_subnet.workload.cidr_block
  source_type               = "CIDR_BLOCK"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = tonumber(each.value)
      max = tonumber(each.value)
    }
  }
}

resource "oci_core_network_security_group_security_rule" "wazuh_goad_agent_enrollment" {
  for_each = {
    for pair in setproduct(var.goad_agent_cidrs, ["1514", "1515"]) : "${pair[0]}-${pair[1]}" => {
      cidr = pair[0]
      port = tonumber(pair[1])
    }
  }

  network_security_group_id = oci_core_network_security_group.wazuh.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = each.value.cidr
  source_type               = "CIDR_BLOCK"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = each.value.port
      max = each.value.port
    }
  }
}

resource "oci_core_network_security_group_security_rule" "agents_ssh_from_bastion" {
  network_security_group_id = oci_core_network_security_group.agents.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = data.oci_core_subnet.bastion.cidr_block
  source_type               = "CIDR_BLOCK"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

module "wazuh_server" {
  source                    = "./modules/wazuh-server"
  tenancy_id                = var.tenancy_id
  compartment_id            = var.compartment_id
  project_name              = var.project_name
  availability_domain_index = var.availability_domain_index
  availability_domain       = var.availability_domain
  image_id                  = var.ubuntu2404_image_id
  subnet_id                 = var.agent_subnet_id
  assign_public_ip          = var.workload_assign_public_ip
  wazuh_nsg_ids             = [oci_core_network_security_group.wazuh.id]
  ssh_public_key            = file(pathexpand(var.ssh_public_key_path))
  freeform_tags             = local.common_freeform_tags
  defined_tags              = var.defined_tags
}

module "compute" {
  source                    = "./modules/compute"
  tenancy_id                = var.tenancy_id
  compartment_id            = var.compartment_id
  project_name              = var.project_name
  availability_domain_index = var.availability_domain_index
  availability_domain       = var.availability_domain
  ol9_image_id              = var.ol9_image_id
  ubuntu2404_image_id       = var.ubuntu2404_image_id
  bastion_subnet_id         = var.bastion_subnet_id
  agent_subnet_id           = var.agent_subnet_id
  bastion_nsg_ids           = [oci_core_network_security_group.bastion.id]
  agent_nsg_ids             = [oci_core_network_security_group.agents.id]
  agent_assign_public_ip    = var.workload_assign_public_ip
  ssh_public_key            = file(pathexpand(var.ssh_public_key_path))
  wazuh_manager_ip          = module.wazuh_server.private_ip
  freeform_tags             = local.common_freeform_tags
  defined_tags              = var.defined_tags
}

resource "oci_opensearch_opensearch_cluster" "oci_logs" {
  count = var.create_oci_opensearch ? 1 : 0

  compartment_id                     = var.compartment_id
  display_name                       = "${var.project_name}-oci-logs-opensearch"
  software_version                   = var.oci_opensearch_software_version
  vcn_id                             = data.oci_core_subnet.workload.vcn_id
  vcn_compartment_id                 = data.oci_core_subnet.workload.compartment_id
  subnet_id                          = var.agent_subnet_id
  subnet_compartment_id              = data.oci_core_subnet.workload.compartment_id
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

module "streaming" {
  count          = var.ingestion_mode == "streaming" ? 1 : 0
  source         = "./modules/streaming"
  compartment_id = var.compartment_id
  project_name   = var.project_name
  freeform_tags  = local.common_freeform_tags
  defined_tags   = var.defined_tags
}

module "logging_audit" {
  source                = "./modules/logging-audit"
  tenancy_id            = var.tenancy_id
  compartment_id        = var.compartment_id
  project_name          = var.project_name
  audit_log_resource_id = var.audit_log_resource_id
  audit_log_category    = var.audit_log_category
  log_retention_days    = var.oci_log_retention_days
  freeform_tags         = local.common_freeform_tags
  defined_tags          = var.defined_tags
}

module "flowlogs" {
  source             = "./modules/flowlogs"
  project_name       = var.project_name
  log_group_id       = module.logging_audit.log_group_id
  resource_ids       = local.managed_flow_log_resource_ids
  log_retention_days = var.oci_log_retention_days
  flow_log_category  = var.flow_log_category
  freeform_tags      = local.common_freeform_tags
  defined_tags       = var.defined_tags
}

module "service_connector" {
  source         = "./modules/service-connector"
  compartment_id = var.compartment_id
  project_name   = var.project_name
  ingestion_mode = var.ingestion_mode
  stream_id      = local.stream_id
  log_group_id   = module.logging_audit.log_group_id
  log_ids        = local.oci_log_ids
  log_sources    = local.oci_log_sources
  freeform_tags  = local.common_freeform_tags
  defined_tags   = var.defined_tags

  depends_on = [
    oci_identity_policy.sch_log_source,
    oci_identity_policy.sch_stream_target,
  ]
}

resource "oci_identity_dynamic_group" "wazuh_consumer" {
  compartment_id = var.tenancy_id
  name           = "${var.project_name}-wazuh-consumer"
  description    = "Wazuh OCI log consumer instance principal."
  matching_rule  = "instance.id = '${module.wazuh_server.instance_id}'"
  freeform_tags  = local.common_freeform_tags
  defined_tags   = var.defined_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_identity_policy" "wazuh_consumer" {
  compartment_id = var.compartment_id
  name           = "${var.project_name}-wazuh-consumer"
  description    = "Allow the Wazuh instance to consume OCI log batches."
  freeform_tags  = local.common_freeform_tags
  defined_tags   = var.defined_tags

  statements = compact([
    var.ingestion_mode == "streaming" ? "Allow dynamic-group ${oci_identity_dynamic_group.wazuh_consumer.name} to use stream-pull in compartment id ${var.compartment_id}" : "",
    var.ingestion_mode == "streaming" ? "Allow dynamic-group ${oci_identity_dynamic_group.wazuh_consumer.name} to inspect streams in compartment id ${var.compartment_id}" : "",
    var.ingestion_mode == "object_storage" ? "Allow dynamic-group ${oci_identity_dynamic_group.wazuh_consumer.name} to read buckets in compartment id ${var.compartment_id}" : "",
    var.ingestion_mode == "object_storage" ? "Allow dynamic-group ${oci_identity_dynamic_group.wazuh_consumer.name} to read objects in compartment id ${var.compartment_id}" : ""
  ])

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_identity_policy" "wazuh_audit_consumer" {
  compartment_id = var.tenancy_id
  name           = "${var.project_name}-wazuh-audit-consumer"
  description    = "Allow the Wazuh instance to read real OCI Audit events."
  freeform_tags  = local.common_freeform_tags
  defined_tags   = var.defined_tags

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.wazuh_consumer.name} to inspect compartments in tenancy",
    "Allow dynamic-group ${oci_identity_dynamic_group.wazuh_consumer.name} to read audit-events in tenancy"
  ]

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_identity_policy" "sch_log_source" {
  for_each       = local.sch_log_source_policy_scope_ids
  compartment_id = var.tenancy_id
  name           = "${var.project_name}-sch-log-source-${each.key}"
  description    = "Allow Service Connector Hub to read OCI logs for Wazuh ingestion."
  freeform_tags  = local.common_freeform_tags
  defined_tags   = var.defined_tags

  statements = [
    "Allow any-user to read log-content in compartment id ${each.value} where request.principal.type='serviceconnector'"
  ]

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_identity_policy" "sch_stream_target" {
  count          = var.ingestion_mode == "streaming" ? 1 : 0
  compartment_id = var.tenancy_id
  name           = "${var.project_name}-sch-stream-target"
  description    = "Allow Service Connector Hub to publish OCI logs to the Wazuh stream."
  freeform_tags  = local.common_freeform_tags
  defined_tags   = var.defined_tags

  statements = [
    "Allow any-user to use stream-push in compartment id ${var.compartment_id} where request.principal.type='serviceconnector'"
  ]

  lifecycle {
    ignore_changes = [defined_tags]
  }
}
