locals {
  standalone_hosts = var.mode == "new_windows" ? toset(["windows01"]) : toset([])
  goad_hosts       = var.mode == "install_goad" ? toset(module.goad_profile.host_names) : toset([])
  managed_hosts    = setunion(local.standalone_hosts, local.goad_hosts)
  managed_targets = {
    for name, instance in oci_core_instance.windows : name => instance.id
  }
  targets = var.mode == "reuse_goad" ? {
    for name in nonsensitive(keys(var.reused_instance_ocids)) : name => var.reused_instance_ocids[name]
  } : local.managed_targets
  target_compartment_id = var.mode == "reuse_goad" ? var.goad_compartment_id : var.compartment_id
  command_object_name   = var.action == "cleanup" ? var.cleanup_object_name : var.install_object_name
  runner_user_data = base64encode(templatefile("${path.module}/cloud-init-runner.yaml.tftpl", {
    action                = var.action
    bootstrap_bucket      = var.bootstrap_bucket
    bootstrap_namespace   = var.bootstrap_namespace
    command_object_name   = local.command_object_name
    goad_vault_secret_id  = var.goad_vault_secret_id
    mode                  = var.mode
    project_name          = var.project_name
    region                = var.region
    target_compartment_id = local.target_compartment_id
    targets_json          = jsonencode(local.targets)
  }))
}

module "goad_profile" {
  source = "../goad-v3"
}

resource "oci_core_instance" "windows" {
  for_each = local.managed_hosts

  availability_domain = var.availability_domain
  compartment_id      = var.compartment_id
  display_name        = "${var.project_name}-${each.value}"
  shape               = var.windows_shape
  freeform_tags = merge(var.freeform_tags, {
    role      = var.mode == "install_goad" ? "goad-host" : "windows-agent"
    goad_host = each.value
  })
  defined_tags = var.defined_tags

  shape_config {
    ocpus         = 2
    memory_in_gbs = 16
  }

  create_vnic_details {
    subnet_id        = var.subnet_id
    assign_public_ip = false
    nsg_ids          = var.nsg_ids
    display_name     = "${var.project_name}-${each.value}-vnic"
  }

  source_details {
    source_type             = "image"
    source_id               = var.windows_image_id
    boot_volume_size_in_gbs = 100
  }

  agent_config {
    are_all_plugins_disabled = false
    plugins_config {
      name          = "Compute Instance Run Command"
      desired_state = "ENABLED"
    }
    plugins_config {
      name          = "Unified Monitoring Agent"
      desired_state = "ENABLED"
    }
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_instance" "runner" {
  count = var.mode == "skip" ? 0 : 1

  availability_domain = var.availability_domain
  compartment_id      = var.compartment_id
  display_name        = "${var.project_name}-windows-orchestrator-${var.action}"
  shape               = var.runner_shape
  freeform_tags       = merge(var.freeform_tags, { role = "windows-orchestrator", action = var.action })
  defined_tags        = var.defined_tags

  shape_config {
    ocpus         = 1
    memory_in_gbs = 4
  }

  create_vnic_details {
    subnet_id        = var.subnet_id
    assign_public_ip = false
    nsg_ids          = var.nsg_ids
    display_name     = "${var.project_name}-windows-orchestrator-vnic"
  }

  source_details {
    source_type = "image"
    source_id   = var.runner_image_id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = local.runner_user_data
  }

  lifecycle {
    ignore_changes       = [defined_tags]
    replace_triggered_by = [terraform_data.runner_action]
  }
}

resource "terraform_data" "runner_action" {
  input = {
    action  = var.action
    mode    = var.mode
    targets = local.targets
  }
}

resource "oci_identity_dynamic_group" "runner" {
  count          = var.mode == "skip" ? 0 : 1
  compartment_id = var.tenancy_id
  name           = "${var.project_name}-windows-orchestrator"
  description    = "Project runner authorized to issue idempotent OCI Agent Run Commands."
  matching_rule  = "instance.id = '${oci_core_instance.runner[0].id}'"
  freeform_tags  = var.freeform_tags
  defined_tags   = var.defined_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_identity_dynamic_group" "targets" {
  count          = var.mode == "skip" ? 0 : 1
  compartment_id = var.tenancy_id
  name           = "${var.project_name}-windows-targets"
  description    = "Windows targets authorized to execute only their own OCI Agent Run Commands."
  matching_rule = "ANY {${join(", ", [
    for instance_id in values(local.targets) : "instance.id = '${instance_id}'"
  ])}}"
  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_identity_policy" "runner" {
  count          = var.mode == "skip" ? 0 : 1
  compartment_id = var.tenancy_id
  name           = "${var.project_name}-windows-run-command"
  description    = "Allow the project runner to issue commands and targets to execute only their commands."
  statements = concat(
    [
      "Allow dynamic-group ${oci_identity_dynamic_group.runner[0].name} to manage instance-agent-command-family in compartment id ${local.target_compartment_id}",
      "Allow dynamic-group ${oci_identity_dynamic_group.targets[0].name} to use instance-agent-command-execution-family in compartment id ${local.target_compartment_id} where request.instance.id=target.instance.id",
    ],
    var.mode == "install_goad" ? [
      "Allow dynamic-group ${oci_identity_dynamic_group.runner[0].name} to read secret-bundles in tenancy where target.secret.id='${var.goad_vault_secret_id}'",
    ] : [],
  )
  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}
