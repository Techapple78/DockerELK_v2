terraform {
  required_version = ">= 1.6.0"

  required_providers {
    vsphere = {
      source  = "vmware/vsphere"
      version = ">= 2.8.0, < 3.0.0"
    }
  }
}
