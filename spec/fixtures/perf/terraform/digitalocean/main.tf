terraform {
  required_version = "~> 1.2"

  required_providers {
    local = {
      version = "~> 2.2"
    }
    null = {
      version = "~> 3.1"
    }
    digitalocean = {
      source = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    tls = {
      version = "~> 3.4"
    }
    random = {
      version = "~> 3.3"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}
