terraform {
  required_version = "~> 1.2"

  required_providers {
    local = {
      version = "~> 2.2"
    }
    null = {
      version = "~> 3.1"
    }
    equinix = {
      source = "equinix/equinix"
      version = "~> 1.6"
    }
    tls = {
      version = "~> 3.4"
    }
    random = {
      version = "~> 3.3"
    }
  }
}

provider "equinix" {
  auth_token = var.metal_auth_token
}
