data "oci_identity_availability_domains" "this" {
  compartment_id = local.effective_tenancy_ocid
}

data "oci_core_images" "ol9" {
  count                    = var.ol9_image_id == "" ? 1 : 0
  compartment_id           = local.effective_tenancy_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "9"
  shape                    = var.linux_agent_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
  state                    = "AVAILABLE"
}

data "oci_core_images" "ubuntu2404" {
  count                    = var.ubuntu2404_image_id == "" ? 1 : 0
  compartment_id           = local.effective_tenancy_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = var.wazuh_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
  state                    = "AVAILABLE"
}

data "oci_core_images" "windows2022" {
  count                    = local.effective_windows_mode == "skip" || var.windows2022_image_id != "" ? 0 : 1
  compartment_id           = local.effective_tenancy_ocid
  operating_system         = "Windows"
  operating_system_version = "Server 2022 Standard"
  shape                    = var.windows_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
  state                    = "AVAILABLE"
}

data "oci_core_shapes" "bastion" {
  compartment_id      = local.effective_compartment_ocid
  availability_domain = local.availability_domain
  image_id            = local.ol9_image_id
  shape               = var.bastion_shape
}

data "oci_core_shapes" "wazuh" {
  compartment_id      = local.effective_compartment_ocid
  availability_domain = local.availability_domain
  image_id            = local.ubuntu2404_image_id
  shape               = var.wazuh_shape
}

data "oci_core_shapes" "linux_agent" {
  compartment_id      = local.effective_compartment_ocid
  availability_domain = local.availability_domain
  image_id            = local.ol9_image_id
  shape               = var.linux_agent_shape
}

data "oci_core_shapes" "windows" {
  count               = local.effective_windows_mode == "skip" ? 0 : 1
  compartment_id      = local.effective_compartment_ocid
  availability_domain = local.availability_domain
  image_id            = local.windows2022_image_id
  shape               = var.windows_shape
}

locals {
  availability_domains            = coalesce(data.oci_identity_availability_domains.this.availability_domains, [])
  availability_domain_index_valid = var.availability_domain_index < length(local.availability_domains)
  availability_domain = var.availability_domain != "" ? var.availability_domain : try(
    data.oci_identity_availability_domains.this.availability_domains[var.availability_domain_index].name,
    try(data.oci_identity_availability_domains.this.availability_domains[0].name, "")
  )
  ol9_image_id = var.ol9_image_id != "" ? var.ol9_image_id : try(data.oci_core_images.ol9[0].images[0].id, "")
  ubuntu2404_image_id = var.ubuntu2404_image_id != "" ? var.ubuntu2404_image_id : try(
    data.oci_core_images.ubuntu2404[0].images[0].id,
    ""
  )
  windows2022_image_id = var.windows2022_image_id != "" ? var.windows2022_image_id : try(
    data.oci_core_images.windows2022[0].images[0].id,
    ""
  )
}

resource "terraform_data" "input_contract" {
  input = {
    ingestion_mode = local.effective_ingestion_mode
    network_mode   = var.network_mode
    windows_mode   = local.effective_windows_mode
  }

  lifecycle {
    precondition {
      condition     = var.availability_domain != "" || local.availability_domain_index_valid
      error_message = "availability_domain_index is outside the availability domains returned for this region."
    }
    precondition {
      condition     = local.effective_tenancy_ocid != "" && local.effective_compartment_ocid != ""
      error_message = "Set tenancy_ocid and compartment_ocid, or their deprecated local aliases."
    }
    precondition {
      condition     = local.ssh_public_key != ""
      error_message = "Set ssh_public_key for ORM or a readable ssh_public_key_path for local CLI use."
    }
    precondition {
      condition = var.network_mode == "create" || (
        var.bastion_subnet_id != "" && var.agent_subnet_id != ""
      )
      error_message = "network_mode=existing requires bastion_subnet_id and agent_subnet_id."
    }
    precondition {
      condition = var.availability_domain != "" || contains(
        [for domain in local.availability_domains : domain.name],
        local.availability_domain
      )
      error_message = "The selected availability domain is not available in this tenancy and region."
    }
    precondition {
      condition     = local.ol9_image_id != "" && local.ubuntu2404_image_id != ""
      error_message = "Compatible Oracle Linux 9 and Ubuntu 24.04 platform images were not found; provide image overrides."
    }
    # OCI provider 8.20 can return null for the Shapes collection even after a
    # successful API response. A non-null empty list remains a hard failure;
    # local wrappers additionally verify shape/image compatibility through OCI
    # CLI before apply when this provider fallback is encountered.
    precondition {
      condition = alltrue([
        data.oci_core_shapes.bastion.shapes == null ? true : length(data.oci_core_shapes.bastion.shapes) > 0,
        data.oci_core_shapes.wazuh.shapes == null ? true : length(data.oci_core_shapes.wazuh.shapes) > 0,
        data.oci_core_shapes.linux_agent.shapes == null ? true : length(data.oci_core_shapes.linux_agent.shapes) > 0,
      ])
      error_message = "One or more selected Linux shapes are unavailable in the selected availability domain."
    }
    precondition {
      condition = local.effective_windows_mode != "reuse_goad" || (
        var.goad_compartment_ocid != "" && length(var.goad_instance_ocids) > 0
      )
      error_message = "reuse_goad requires goad_compartment_ocid and goad_instance_ocids."
    }
    precondition {
      condition     = local.effective_windows_mode != "install_goad" || var.goad_vault_secret_id != ""
      error_message = "install_goad requires goad_vault_secret_id; credentials must remain in OCI Vault."
    }
    precondition {
      condition     = local.effective_windows_mode == "skip" || local.windows2022_image_id != ""
      error_message = "A compatible Windows Server 2022 image was not found; provide windows2022_image_id."
    }
    precondition {
      condition = !var.create_oci_opensearch || var.oci_opensearch_security_mode == "DISABLED" || (
        var.oci_opensearch_master_password_hash != ""
      )
      error_message = "Managed OpenSearch security requires oci_opensearch_master_password_hash."
    }
  }
}
