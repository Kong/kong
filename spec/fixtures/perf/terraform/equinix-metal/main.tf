terraform {
  required_version = ">= 0.14"

  required_providers {
    local = {
      version = "~> 1.2"
    }
    null = {
      version = "~> 2.1"
    }
    metal = {
      source = "equinix/metal"
      version = "~> 3.2"
    }
    tls = {
      version = "~> 2.0"
    }
    random = {
      version = "3.1.0"
    }
  }
}

provider "metal" {
  auth_token = var.metal_auth_token
}
