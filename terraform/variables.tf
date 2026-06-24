variable "region" {
  type        = string
  description = "OCI region for the lab."
  default     = "eu-frankfurt-1"
}

variable "oci_config_profile" {
  type        = string
  default     = "cap"
  description = "OCI CLI config profile used by the Terraform provider."
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
  description = "SSH public key path used for bastion and Linux instances."
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

variable "windows_mode" {
  type        = string
  default     = "auto"
  description = "One of auto, skip, new_windows, reuse_goad, install_goad."

  validation {
    condition     = contains(["auto", "skip", "new_windows", "reuse_goad", "install_goad"], var.windows_mode)
    error_message = "windows_mode must be auto, skip, new_windows, reuse_goad, or install_goad."
  }
}

variable "enable_log_analytics_bridge" {
  type        = bool
  default     = true
  description = "Forward OS logs, EDR/Sysmon, and Wazuh alerts to OCI Log Analytics."
}

variable "defined_tags" {
  type        = map(string)
  default     = {}
  description = "Optional defined tags."
}
