locals {
  common_freeform_tags = {
    project   = var.project_name
    component = "wazuh-detection-lab"
  }
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
