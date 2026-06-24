locals {
  user_data = base64encode(templatefile("${path.module}/cloud-init-wazuh.yaml.tftpl", {
    project_name = var.project_name
  }))
}

resource "oci_core_instance" "this" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_id
  display_name        = "${var.project_name}-wazuh-aio"
  shape               = "VM.Standard.E6.Flex"
  freeform_tags       = merge(var.freeform_tags, { role = "wazuh-server" })
  defined_tags        = var.defined_tags

  shape_config {
    ocpus         = 4
    memory_in_gbs = 16
  }

  create_vnic_details {
    subnet_id        = var.subnet_id
    assign_public_ip = var.assign_public_ip
    nsg_ids          = var.wazuh_nsg_ids
    display_name     = "${var.project_name}-wazuh-vnic"
  }

  source_details {
    source_type             = "image"
    source_id               = var.image_id
    boot_volume_size_in_gbs = 200
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = local.user_data
  }
}
