locals {
  agent_user_data = {
    ol9 = base64encode(templatefile("${path.module}/cloud-init-linux-agent.yaml.tftpl", {
      agent_name                  = "${var.project_name}-ol9-agent"
      bootstrap_bucket            = var.bootstrap_bucket
      bootstrap_namespace         = var.bootstrap_namespace
      bootstrap_status_prefix     = var.bootstrap_status_prefix
      os_family                   = "ol"
      region                      = var.region
      wazuh_manager_ip            = var.wazuh_manager_ip
      wazuh_repository_key_sha256 = var.wazuh_repository_key_sha256
      wazuh_version               = var.wazuh_version
    }))
    ubuntu = base64encode(templatefile("${path.module}/cloud-init-linux-agent.yaml.tftpl", {
      agent_name                  = "${var.project_name}-ubuntu-agent"
      bootstrap_bucket            = var.bootstrap_bucket
      bootstrap_namespace         = var.bootstrap_namespace
      bootstrap_status_prefix     = var.bootstrap_status_prefix
      os_family                   = "ubuntu"
      region                      = var.region
      wazuh_manager_ip            = var.wazuh_manager_ip
      wazuh_repository_key_sha256 = var.wazuh_repository_key_sha256
      wazuh_version               = var.wazuh_version
    }))
  }
}

resource "oci_core_instance" "bastion" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_id
  display_name        = "${var.project_name}-bastion"
  shape               = var.bastion_shape
  freeform_tags       = merge(var.freeform_tags, { role = "bastion" })
  defined_tags        = var.defined_tags

  shape_config {
    ocpus         = 1
    memory_in_gbs = 4
  }

  create_vnic_details {
    subnet_id        = var.bastion_subnet_id
    assign_public_ip = true
    nsg_ids          = var.bastion_nsg_ids
    display_name     = "${var.project_name}-bastion-vnic"
  }

  source_details {
    source_type = "image"
    source_id   = var.ubuntu2404_image_id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }
}
resource "oci_core_instance" "ol9_agent" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_id
  display_name        = "${var.project_name}-ol9-agent"
  shape               = var.agent_shape
  freeform_tags       = merge(var.freeform_tags, { role = "linux-agent", os = "ol9" })
  defined_tags        = var.defined_tags

  shape_config {
    ocpus         = 1
    memory_in_gbs = 4
  }

  create_vnic_details {
    subnet_id        = var.agent_subnet_id
    assign_public_ip = false
    nsg_ids          = var.agent_nsg_ids
    display_name     = "${var.project_name}-ol9-agent-vnic"
  }

  source_details {
    source_type = "image"
    source_id   = var.ol9_image_id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = local.agent_user_data.ol9
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_instance" "ubuntu_agent" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_id
  display_name        = "${var.project_name}-ubuntu-agent"
  shape               = var.agent_shape
  freeform_tags       = merge(var.freeform_tags, { role = "linux-agent", os = "ubuntu24" })
  defined_tags        = var.defined_tags

  shape_config {
    ocpus         = 1
    memory_in_gbs = 4
  }

  create_vnic_details {
    subnet_id        = var.agent_subnet_id
    assign_public_ip = false
    nsg_ids          = var.agent_nsg_ids
    display_name     = "${var.project_name}-ubuntu-agent-vnic"
  }

  source_details {
    source_type = "image"
    source_id   = var.ubuntu2404_image_id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = local.agent_user_data.ubuntu
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }
}
