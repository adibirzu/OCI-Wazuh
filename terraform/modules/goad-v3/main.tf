locals {
  upstream_commit = "992307adf944b934a3b76a2f56a637104c54b805"
  host_names      = ["braavos", "castelblack", "kingslanding", "meereen", "winterfell"]
}

output "upstream_commit" {
  value = local.upstream_commit
}

output "host_names" {
  value = local.host_names
}
