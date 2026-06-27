terraform {
  required_version = ">= 1.5.7, < 1.6.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.20"
    }
  }
}
