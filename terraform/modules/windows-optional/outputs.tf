output "managed_instance_ids" {
  value = values(local.managed_targets)
}
output "target_instance_ids" {
  value     = values(local.targets)
  sensitive = true
}
output "runner_instance_id" {
  value = try(oci_core_instance.runner[0].id, null)
}
output "target_names" {
  value = sort(keys(local.targets))
}

output "target_instance_map" {
  value     = local.targets
  sensitive = true
}

output "target_dynamic_group_id" {
  value = try(oci_identity_dynamic_group.targets[0].id, null)
}

output "target_dynamic_group_name" {
  value = try(oci_identity_dynamic_group.targets[0].name, null)
}

output "goad_upstream_commit" {
  value = module.goad_profile.upstream_commit
}
