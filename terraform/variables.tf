variable "region" {
  type        = string
  description = "OCI region for the lab."
  default     = "eu-frankfurt-1"
}

variable "oci_config_profile" {
  type        = string
  default     = ""
  description = "OCI CLI config profile used by local Terraform. Leave empty for OCI Resource Manager."
}

variable "compartment_id" {
  type        = string
  description = "Target compartment OCID. Leave empty only when a wrapper creates the compartment."
  default     = ""
  sensitive   = true
}

variable "tenancy_id" {
  type        = string
  description = "Tenancy OCID used for availability-domain and platform-image lookups."
  sensitive   = true
}

variable "project_name" {
  type        = string
  default     = "oci-wazuh-demo"
  description = "Resource name and tag prefix."
}

variable "operator_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "CIDR allowed to reach bastion SSH. Restrict for real deployments."
}

variable "ssh_public_key_path" {
  type        = string
  default     = "~/.ssh/id_rsa.pub"
  description = "Local SSH public key path used for bastion and Linux instances when ssh_public_key is empty."
}

variable "ssh_public_key" {
  type        = string
  default     = ""
  description = "SSH public key content. Required for OCI Resource Manager deployments; local deployments can use ssh_public_key_path instead."
  sensitive   = true
}

variable "ssh_private_key_path" {
  type        = string
  default     = "~/.ssh/id_rsa"
  description = "SSH private key path used by generated helper commands."
}

variable "availability_domain_index" {
  type        = number
  default     = 0
  description = "Availability domain index."
}

variable "availability_domain" {
  type        = string
  description = "Resolved OCI availability-domain name."
}

variable "ol9_image_id" {
  type        = string
  description = "Oracle Linux 9 image OCID."
}

variable "ubuntu2404_image_id" {
  type        = string
  description = "Ubuntu 24.04 image OCID."
}

variable "bastion_subnet_id" {
  type        = string
  description = "Existing public subnet for bastion."
}

variable "agent_subnet_id" {
  type        = string
  description = "Existing subnet for Wazuh and agents."
}

variable "workload_assign_public_ip" {
  type        = bool
  default     = false
  description = "Assign public IPs to Wazuh and Linux agents. Intended only for controlled development fallback subnets."
}

variable "ingestion_mode" {
  type        = string
  default     = "streaming"
  description = "One of streaming, object_storage, direct_api, log_analytics_bridge."

  validation {
    condition     = contains(["streaming", "object_storage", "direct_api", "log_analytics_bridge"], var.ingestion_mode)
    error_message = "ingestion_mode must be streaming, object_storage, direct_api, or log_analytics_bridge."
  }
}

variable "audit_log_resource_id" {
  type        = string
  default     = ""
  description = "Audit resource OCID. Empty means tenancy-wide audit ingestion using tenancy_id."
  sensitive   = true
}

variable "audit_log_category" {
  type        = string
  default     = "all"
  description = "OCI Audit log category. Default all works for tenancy-wide audit logs; set Audit if your tenancy requires the older category."
}

variable "flow_log_resource_ids" {
  type        = list(string)
  default     = []
  description = "Subnet or VNIC OCIDs for VCN Flow Logs. Empty means agent_subnet_id."
  sensitive   = true
}

variable "flow_log_category" {
  type        = string
  default     = "subnet"
  description = "Fallback OCI Flow Logs category. Subnet, VCN, and VNIC OCIDs are auto-mapped to subnet/vcn/vnic."
}

variable "existing_flow_logs" {
  type = list(object({
    compartment_id = string
    log_group_id   = string
    log_id         = string
  }))
  default     = []
  description = "Existing OCI Flow Logs to reuse instead of creating new ones. Use this when a subnet/VCN/VNIC already has Flow Logs enabled."
}

variable "oci_log_retention_days" {
  type        = number
  default     = 30
  description = "OCI Logging retention duration for VCN Flow logs."
}

variable "windows_mode" {
  type        = string
  default     = "auto"
  description = "One of auto, skip, new_windows, reuse_goad, install_goad."

  validation {
    condition     = contains(["auto", "skip", "new_windows", "reuse_goad", "install_goad"], var.windows_mode)
    error_message = "windows_mode must be auto, skip, new_windows, reuse_goad, or install_goad."
  }
}

variable "goad_agent_cidrs" {
  type        = list(string)
  default     = []
  description = "Optional GOAD or reused Windows host CIDRs allowed to enroll and send events to Wazuh on 1514/1515."
}

variable "enable_log_analytics_bridge" {
  type        = bool
  default     = true
  description = "Forward OS logs, EDR/Sysmon, and Wazuh alerts to OCI Log Analytics."
}

variable "create_oci_opensearch" {
  type        = bool
  default     = false
  description = "Create an OCI Search Service with OpenSearch cluster for dedicated OCI Audit and VCN Flow indices. Disabled by default; Wazuh AIO indexer is the default backend."
}

variable "oci_opensearch_software_version" {
  type        = string
  default     = "2.19.0"
  description = "OCI OpenSearch software version used only when create_oci_opensearch is true. Confirm supported versions in your region with the OCI CLI before enabling."
}

variable "oci_opensearch_security_mode" {
  type        = string
  default     = "ENFORCING"
  description = "Security mode for the optional OCI OpenSearch cluster."

  validation {
    condition     = contains(["DISABLED", "PERMISSIVE", "ENFORCING"], var.oci_opensearch_security_mode)
    error_message = "oci_opensearch_security_mode must be DISABLED, PERMISSIVE, or ENFORCING."
  }
}

variable "oci_opensearch_master_user_name" {
  type        = string
  default     = "admin"
  description = "Master username for the optional OCI OpenSearch cluster."
}

variable "oci_opensearch_master_password" {
  type        = string
  default     = ""
  description = "Plaintext master password used by make opensearch-oci when configuring templates and dashboards. Keep this in local tfvars, environment variables, or OCI Vault; Terraform does not send this value to OCI."
  sensitive   = true
}

variable "oci_opensearch_master_password_hash" {
  type        = string
  default     = ""
  description = "Stable bcrypt hash for the optional OCI OpenSearch master password. Required by OCI OpenSearch when create_oci_opensearch is true and security mode is not DISABLED."
  sensitive   = true
}

variable "oci_opensearch_data_node_count" {
  type        = number
  default     = 1
  description = "Data node count for the optional OCI OpenSearch cluster."
}

variable "oci_opensearch_data_node_ocpus" {
  type        = number
  default     = 1
  description = "OCPUs per data node for the optional OCI OpenSearch cluster."
}

variable "oci_opensearch_data_node_memory_gb" {
  type        = number
  default     = 8
  description = "Memory per data node for the optional OCI OpenSearch cluster."
}

variable "oci_opensearch_data_node_storage_gb" {
  type        = number
  default     = 50
  description = "Storage per data node for the optional OCI OpenSearch cluster."
}

variable "oci_opensearch_master_node_count" {
  type        = number
  default     = 1
  description = "Master node count for the optional OCI OpenSearch cluster."
}

variable "oci_opensearch_master_node_ocpus" {
  type        = number
  default     = 1
  description = "OCPUs per master node for the optional OCI OpenSearch cluster."
}

variable "oci_opensearch_master_node_memory_gb" {
  type        = number
  default     = 8
  description = "Memory per master node for the optional OCI OpenSearch cluster."
}

variable "oci_opensearch_dashboard_node_count" {
  type        = number
  default     = 1
  description = "OpenDashboard node count for the optional OCI OpenSearch cluster."
}

variable "oci_opensearch_dashboard_node_ocpus" {
  type        = number
  default     = 1
  description = "OCPUs per OpenDashboard node for the optional OCI OpenSearch cluster."
}

variable "oci_opensearch_dashboard_node_memory_gb" {
  type        = number
  default     = 8
  description = "Memory per OpenDashboard node for the optional OCI OpenSearch cluster."
}

variable "defined_tags" {
  type        = map(string)
  default     = {}
  description = "Optional defined tags."
}
