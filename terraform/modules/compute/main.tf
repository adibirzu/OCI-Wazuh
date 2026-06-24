locals {
  ad_name = var.availability_domain
  agent_user_data = {
    ol9    = base64encode(templatefile("${path.module}/cloud-init-linux-agent.yaml.tftpl", { wazuh_manager_ip = var.wazuh_manager_ip, os_family = "ol" }))
    ubuntu = base64encode(templatefile("${path.module}/cloud-init-linux-agent.yaml.tftpl", { wazuh_manager_ip = var.wazuh_manager_ip, os_family = "ubuntu" }))
  }
}

resource "oci_core_instance" "bastion" {
  availability_domain = local.ad_name
  compartment_id      = var.compartment_id
  display_name        = "${var.project_name}-bastion"
  shape               = "VM.Standard.E6.Flex"
  freeform_tags       = merge(var.freeform_tags, { role = "bastion" })
  defined_tags        = var.defined_tags

  shape_config {
    ocpus         = 4
    memory_in_gbs = 32
  }

  create_vnic_details {
    subnet_id        = var.bastion_subnet_id
    assign_public_ip = true
    nsg_ids          = var.bastion_nsg_ids
  }

  source_details {
    source_type = "image"
    source_id   = var.ubuntu2404_image_id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }
}

resource "oci_core_instance" "ol9_agent" {
  availability_domain = local.ad_name
  compartment_id      = var.compartment_id
  display_name        = "${var.project_name}-ol9-agent"
  shape               = "VM.Standard.E5.Flex"
  freeform_tags       = merge(var.freeform_tags, { role = "linux-agent", os = "ol9" })
  defined_tags        = var.defined_tags

  shape_config {
    ocpus         = 1
    memory_in_gbs = 4
  }

  create_vnic_details {
    subnet_id        = var.agent_subnet_id
    assign_public_ip = var.agent_assign_public_ip
    nsg_ids          = var.agent_nsg_ids
  }

  source_details {
    source_type = "image"
    source_id   = var.ol9_image_id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = local.agent_user_data.ol9
  }
}

resource "oci_core_instance" "ubuntu_agent" {
  availability_domain = local.ad_name
  compartment_id      = var.compartment_id
  display_name        = "${var.project_name}-ubuntu-agent"
  shape               = "VM.Standard.E5.Flex"
  freeform_tags       = merge(var.freeform_tags, { role = "linux-agent", os = "ubuntu24" })
  defined_tags        = var.defined_tags

  shape_config {
    ocpus         = 1
    memory_in_gbs = 4
  }

  create_vnic_details {
    subnet_id        = var.agent_subnet_id
    assign_public_ip = var.agent_assign_public_ip
    nsg_ids          = var.agent_nsg_ids
  }

  source_details {
    source_type = "image"
    source_id   = var.ubuntu2404_image_id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = local.agent_user_data.ubuntu
  }
}
