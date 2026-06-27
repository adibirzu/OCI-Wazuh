locals {
  user_data = base64encode(templatefile("${path.module}/cloud-init-wazuh.yaml.tftpl", {
    audit_compartment_id      = var.audit_compartment_id
    bootstrap_bucket          = var.bootstrap_bucket
    bootstrap_bundle_object   = var.bootstrap_bundle_object
    bootstrap_bundle_sha256   = var.bootstrap_bundle_sha256
    bootstrap_manifest_object = var.bootstrap_manifest_object
    bootstrap_namespace       = var.bootstrap_namespace
    bootstrap_status_prefix   = var.bootstrap_status_prefix
    ingestion_mode            = var.ingestion_mode
    object_bucket             = var.object_bucket
    object_namespace          = var.object_namespace
    object_prefix             = var.object_prefix
    project_name              = var.project_name
    region                    = var.region
    stream_endpoint           = var.stream_endpoint
    stream_id                 = var.stream_id
    wazuh_installer_sha256    = var.wazuh_installer_sha256
    wazuh_version             = var.wazuh_version
  }))
}

resource "oci_core_instance" "this" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_id
  display_name        = "${var.project_name}-wazuh-aio"
  shape               = var.shape
  freeform_tags       = merge(var.freeform_tags, { role = "wazuh-server" })
  defined_tags        = var.defined_tags

  shape_config {
    ocpus         = 4
    memory_in_gbs = 16
  }

  create_vnic_details {
    subnet_id        = var.subnet_id
    assign_public_ip = false
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

  lifecycle {
    ignore_changes = [defined_tags]
  }
}
