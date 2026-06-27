variable "region" {
  type        = string
  description = "OCI region for the lab. Resource Manager supplies this automatically."
  default     = "eu-frankfurt-1"
}

variable "tenancy_ocid" {
  type        = string
  description = "Tenancy OCID. Canonical Resource Manager identity input."
  default     = ""
  sensitive   = true

  validation {
    condition     = var.tenancy_ocid == "" || can(regex("^ocid1\\.tenancy\\.", var.tenancy_ocid))
    error_message = "tenancy_ocid must be empty or a tenancy OCID."
  }
}

variable "compartment_ocid" {
  type        = string
  description = "Compartment OCID in which demo resources are created."
  default     = ""
  sensitive   = true

  validation {
    condition     = var.compartment_ocid == "" || can(regex("^ocid1\\.compartment\\.", var.compartment_ocid))
    error_message = "compartment_ocid must be empty or a compartment OCID."
  }
}

variable "tenancy_id" {
  type        = string
  description = "Deprecated local-CLI alias for tenancy_ocid; remove after the v0.5 transition release."
  default     = ""
  sensitive   = true
}

variable "compartment_id" {
  type        = string
  description = "Deprecated local-CLI alias for compartment_ocid; remove after the v0.5 transition release."
  default     = ""
  sensitive   = true
}

variable "oci_config_profile" {
  type        = string
  description = "Deprecated compatibility input. Set OCI_CONFIG_PROFILE for local CLI use; ORM uses instance credentials."
  default     = ""
}

variable "project_name" {
  type        = string
  default     = "oci-wazuh-demo"
  description = "Resource name and mandatory project tag value."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,29}$", var.project_name))
    error_message = "project_name must be 3-30 lowercase letters, digits, or hyphens and start with a letter."
  }
}

variable "operator_cidr" {
  type        = string
  description = "Single operator CIDR allowed to reach bastion SSH. Unrestricted CIDRs are rejected."

  validation {
    condition     = can(cidrnetmask(var.operator_cidr)) && !contains(["0.0.0.0/0", "::/0"], var.operator_cidr)
    error_message = "operator_cidr must be a valid restricted CIDR; 0.0.0.0/0 and ::/0 are not allowed."
  }
}

variable "ssh_public_key" {
  type        = string
  default     = ""
  description = "SSH public key content. Required by Resource Manager; local CLI can use ssh_public_key_path."
  sensitive   = true
}

variable "ssh_public_key_path" {
  type        = string
  default     = "~/.ssh/id_rsa.pub"
  description = "Deprecated local-only public key path used when ssh_public_key is empty."
}

variable "ssh_private_key_path" {
  type        = string
  default     = "~/.ssh/id_rsa"
  description = "Local-only private key path printed in helper commands; never consumed by Resource Manager."
}

variable "network_mode" {
  type        = string
  default     = "create"
  description = "Create an isolated network or use explicitly supplied existing subnets."

  validation {
    condition     = contains(["create", "existing"], var.network_mode)
    error_message = "network_mode must be create or existing."
  }
}

variable "vcn_cidr" {
  type        = string
  default     = "10.20.0.0/16"
  description = "VCN CIDR used only when network_mode=create."
}

variable "bastion_subnet_cidr" {
  type        = string
  default     = "10.20.10.0/24"
  description = "Public bastion subnet CIDR used only when network_mode=create."
}

variable "workload_subnet_cidr" {
  type        = string
  default     = "10.20.20.0/24"
  description = "Private workload subnet CIDR used only when network_mode=create."
}

variable "bastion_subnet_id" {
  type        = string
  default     = ""
  description = "Existing public bastion subnet OCID; required when network_mode=existing."
  sensitive   = true
}

variable "agent_subnet_id" {
  type        = string
  default     = ""
  description = "Existing private workload subnet OCID; required when network_mode=existing."
  sensitive   = true
}

variable "workload_assign_public_ip" {
  type        = bool
  default     = false
  description = "Deprecated development input. Workloads must remain private in M11."

  validation {
    condition     = !var.workload_assign_public_ip
    error_message = "M11 does not permit public IPs on Wazuh, Linux, Windows, or GOAD workloads."
  }
}

variable "availability_domain" {
  type        = string
  default     = ""
  description = "Optional availability-domain name override. Empty selects availability_domain_index."
}

variable "availability_domain_index" {
  type        = number
  default     = 0
  description = "Zero-based availability-domain index used when availability_domain is empty."

  validation {
    condition     = var.availability_domain_index >= 0 && floor(var.availability_domain_index) == var.availability_domain_index
    error_message = "availability_domain_index must be a non-negative integer."
  }
}

variable "ol9_image_id" {
  type        = string
  default     = ""
  description = "Optional Oracle Linux 9 image OCID override."
  sensitive   = true
}

variable "ubuntu2404_image_id" {
  type        = string
  default     = ""
  description = "Optional Canonical Ubuntu 24.04 image OCID override."
  sensitive   = true
}

variable "windows2022_image_id" {
  type        = string
  default     = ""
  description = "Optional Windows Server 2022 image OCID override."
  sensitive   = true
}

variable "bastion_shape" {
  type        = string
  default     = "VM.Standard.E5.Flex"
  description = "Regional flex shape for the bastion."
}

variable "wazuh_shape" {
  type        = string
  default     = "VM.Standard.E5.Flex"
  description = "Regional flex shape for the Wazuh all-in-one host."
}

variable "linux_agent_shape" {
  type        = string
  default     = "VM.Standard.E5.Flex"
  description = "Regional flex shape for Linux agents."
}

variable "windows_shape" {
  type        = string
  default     = "VM.Standard.E5.Flex"
  description = "Regional flex shape for standalone Windows and GOAD hosts."
}

variable "wazuh_version" {
  type        = string
  default     = "4.14.5"
  description = "Pinned Wazuh 4.14 patch version used by managers and agents."

  validation {
    condition     = can(regex("^4\\.14\\.[0-9]+$", var.wazuh_version))
    error_message = "wazuh_version must remain on the approved 4.14.x line."
  }
}

variable "wazuh_installer_sha256" {
  type        = string
  default     = "5ca5d3b605642b15935a6efdea731a6113a4a838a13caf71d2dd4a8feb32d69f"
  description = "SHA-256 for the pinned Wazuh 4.14 all-in-one installer script."
}

variable "wazuh_repository_key_sha256" {
  type        = string
  default     = "a378ca8dfa6b72122df288f64a0cde54f1cbfa3db9b43e6865cb73def35b5b17"
  description = "SHA-256 for the Wazuh repository signing key."
}

variable "ingestion_mode" {
  type        = string
  default     = "streaming"
  description = "OCI log ingestion path. log_analytics_bridge is accepted as a deprecated direct_api alias."

  validation {
    condition     = contains(["streaming", "object_storage", "direct_api", "log_analytics_bridge"], var.ingestion_mode)
    error_message = "ingestion_mode must be streaming, object_storage, direct_api, or log_analytics_bridge."
  }
}

variable "audit_log_resource_id" {
  type        = string
  default     = ""
  description = "Optional Audit resource OCID. Empty uses tenancy-wide Audit API ingestion."
  sensitive   = true

  validation {
    condition = var.audit_log_resource_id == "" || can(regex(
      "^ocid1\\.(tenancy|compartment)\\.",
      var.audit_log_resource_id,
    ))
    error_message = "audit_log_resource_id must be empty or a tenancy/compartment OCID for Audit API scope."
  }
}

variable "audit_log_category" {
  type        = string
  default     = "all"
  description = "Audit category retained for compatibility with tenancies that expose an Audit service log."
}

variable "flow_log_resource_ids" {
  type        = list(string)
  default     = []
  description = "Optional subnet, VCN, or VNIC OCIDs for Flow Logs. Empty selects the workload subnet."
  sensitive   = true
}

variable "flow_log_resource_compartment_id" {
  type        = string
  default     = ""
  description = "Optional compartment override for managed flow_log_resource_ids."
  sensitive   = true
}

variable "flow_log_category" {
  type        = string
  default     = "subnet"
  description = "Fallback Flow Logs category for resource IDs whose OCID type cannot be inferred."
}

variable "existing_flow_logs" {
  type = list(object({
    compartment_id = string
    log_group_id   = string
    log_id         = string
  }))
  default     = []
  description = "Existing OCI Flow Logs to route without taking ownership of them."
}

variable "oci_log_retention_days" {
  type        = number
  default     = 30
  description = "OCI Logging retention duration."

  validation {
    condition = (
      var.oci_log_retention_days >= 30 && var.oci_log_retention_days <= 180 && var.oci_log_retention_days % 30 == 0
    )
    error_message = "oci_log_retention_days must be a 30-day increment from 30 through 180."
  }
}

variable "enable_log_analytics_bridge" {
  type        = bool
  default     = true
  description = "Provision declarative OCI Logging and Log Analytics bridge resources."
}

variable "log_analytics_namespace" {
  type        = string
  default     = ""
  description = "Optional Log Analytics namespace override. Empty resolves the tenancy namespace."
}

variable "object_storage_namespace" {
  type        = string
  default     = ""
  description = "Optional Object Storage namespace override. Empty resolves the tenancy namespace through the OCI provider."
  sensitive   = true
}

variable "windows_mode" {
  type        = string
  default     = "skip"
  description = "Windows path. auto is accepted as a deprecated alias for skip."

  validation {
    condition     = contains(["auto", "skip", "new_windows", "reuse_goad", "install_goad"], var.windows_mode)
    error_message = "windows_mode must be skip, new_windows, reuse_goad, install_goad, or deprecated auto."
  }
}

variable "goad_compartment_ocid" {
  type        = string
  default     = ""
  description = "Compartment containing reused GOAD hosts. Required for reuse_goad."
  sensitive   = true
}

variable "goad_instance_ocids" {
  type        = map(string)
  default     = {}
  description = "JSON map of GOAD host names to existing instance OCIDs for reuse_goad."
  sensitive   = true

  validation {
    condition = alltrue([
      for name, instance_id in var.goad_instance_ocids :
      can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,62}$", name)) && can(regex("^ocid1\\.instance\\.", instance_id))
    ])
    error_message = "goad_instance_ocids must map safe host names to OCI instance OCIDs."
  }
}

variable "goad_agent_cidrs" {
  type        = list(string)
  default     = []
  description = "Reachable GOAD CIDRs allowed to enroll with Wazuh without modifying shared routes."

  validation {
    condition     = alltrue([for cidr in var.goad_agent_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every goad_agent_cidrs entry must be a valid CIDR."
  }
}

variable "reuse_goad_action" {
  type        = string
  default     = "install"
  description = "Install missing project-owned components or remove only project-owned components."

  validation {
    condition     = contains(["install", "cleanup"], var.reuse_goad_action)
    error_message = "reuse_goad_action must be install or cleanup."
  }
}

variable "goad_vault_secret_id" {
  type        = string
  default     = ""
  description = "Vault secret OCID containing GOAD runtime credentials; values never enter Terraform state."
  sensitive   = true

  validation {
    condition     = var.goad_vault_secret_id == "" || can(regex("^ocid1\\.vaultsecret\\.", var.goad_vault_secret_id))
    error_message = "goad_vault_secret_id must be empty or an OCI Vault secret OCID."
  }
}

variable "create_oci_opensearch" {
  type        = bool
  default     = false
  description = "Create an optional OCI Search with OpenSearch cluster."
}

variable "oci_opensearch_software_version" {
  type        = string
  default     = "2.19.0"
  description = "OpenSearch software version. Confirm regional availability before enabling."
}

variable "oci_opensearch_security_mode" {
  type        = string
  default     = "ENFORCING"
  description = "OpenSearch security mode."

  validation {
    condition     = contains(["DISABLED", "PERMISSIVE", "ENFORCING"], var.oci_opensearch_security_mode)
    error_message = "oci_opensearch_security_mode must be DISABLED, PERMISSIVE, or ENFORCING."
  }
}

variable "oci_opensearch_master_user_name" {
  type        = string
  default     = "admin"
  description = "Master username for optional OpenSearch."
}

variable "oci_opensearch_master_password" {
  type        = string
  default     = ""
  description = "Local-only plaintext used by the post-health API bootstrap; never sent as a Terraform resource argument."
  sensitive   = true
}

variable "oci_opensearch_master_password_hash" {
  type        = string
  default     = ""
  description = "Stable bcrypt hash required when OpenSearch security is enabled."
  sensitive   = true
}

variable "oci_opensearch_data_node_count" {
  type    = number
  default = 1
}
variable "oci_opensearch_data_node_ocpus" {
  type    = number
  default = 1
}
variable "oci_opensearch_data_node_memory_gb" {
  type    = number
  default = 8
}
variable "oci_opensearch_data_node_storage_gb" {
  type    = number
  default = 50
}
variable "oci_opensearch_master_node_count" {
  type    = number
  default = 1
}
variable "oci_opensearch_master_node_ocpus" {
  type    = number
  default = 1
}
variable "oci_opensearch_master_node_memory_gb" {
  type    = number
  default = 8
}
variable "oci_opensearch_dashboard_node_count" {
  type    = number
  default = 1
}
variable "oci_opensearch_dashboard_node_ocpus" {
  type    = number
  default = 1
}
variable "oci_opensearch_dashboard_node_memory_gb" {
  type    = number
  default = 8
}

variable "defined_tags" {
  type        = map(string)
  default     = {}
  description = "Optional defined tags merged with mandatory free-form project tags."
}
