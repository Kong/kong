terraform {
  required_version = "~> 1.2"

  required_providers {
    local = {
      version = "~> 2.2"
    }
    null = {
      version = "~> 3.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
    tls = {
      version = "~> 3.4"
    }
    random = {
      version = "~> 3.3"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
