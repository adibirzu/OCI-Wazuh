locals {
  windows_install_script = templatefile("${path.root}/modules/windows-optional/install.ps1.tftpl", {
    project_name         = var.project_name
    sysmon_config_base64 = filebase64("${local.asset_root}/windows/sysmon-config.xml")
    sysmon_zip_sha256    = "6d48089c7fae14944c82b06767b79ccba3cc26d13218a4227ed28c90f80d0f0e"
    wazuh_manager_ip     = module.wazuh_server.private_ip
    wazuh_msi_sha256     = "bf35197fee30092d78aad648299e8fd3aba8a0f9bc7d5edebce483a0b2c8e38e"
    wazuh_version        = var.wazuh_version
    windows_mode         = local.effective_windows_mode
  })
  windows_cleanup_script = templatefile("${path.root}/modules/windows-optional/cleanup.ps1.tftpl", {
    project_name = var.project_name
  })
}

resource "oci_objectstorage_object" "windows_install" {
  namespace    = local.bootstrap_namespace
  bucket       = oci_objectstorage_bucket.bootstrap.name
  object       = "windows/install.ps1"
  content      = local.windows_install_script
  content_type = "text/plain"
  metadata = {
    sha256                    = sha256(local.windows_install_script)
    project                   = var.project_name
    configuration_fingerprint = local.configuration_fingerprint
  }
}

resource "oci_objectstorage_object" "windows_cleanup" {
  namespace    = local.bootstrap_namespace
  bucket       = oci_objectstorage_bucket.bootstrap.name
  object       = "windows/cleanup.ps1"
  content      = local.windows_cleanup_script
  content_type = "text/plain"
  metadata = {
    sha256                    = sha256(local.windows_cleanup_script)
    project                   = var.project_name
    configuration_fingerprint = local.configuration_fingerprint
  }
}

module "windows" {
  source                = "./modules/windows-optional"
  mode                  = local.effective_windows_mode
  action                = local.effective_reuse_goad_action
  tenancy_id            = local.effective_tenancy_ocid
  compartment_id        = local.effective_compartment_ocid
  goad_compartment_id   = var.goad_compartment_ocid
  reused_instance_ocids = var.goad_instance_ocids
  goad_vault_secret_id  = var.goad_vault_secret_id
  project_name          = var.project_name
  availability_domain   = local.availability_domain
  windows_image_id      = local.windows2022_image_id
  runner_image_id       = local.ol9_image_id
  windows_shape         = var.windows_shape
  runner_shape          = var.linux_agent_shape
  subnet_id             = module.network.workload_subnet_id
  nsg_ids               = [module.network.agent_nsg_id]
  ssh_public_key        = local.ssh_public_key
  bootstrap_namespace   = local.bootstrap_namespace
  bootstrap_bucket      = oci_objectstorage_bucket.bootstrap.name
  install_object_name   = oci_objectstorage_object.windows_install.object
  cleanup_object_name   = oci_objectstorage_object.windows_cleanup.object
  region                = var.region
  freeform_tags         = local.common_freeform_tags
  defined_tags          = var.defined_tags
}
