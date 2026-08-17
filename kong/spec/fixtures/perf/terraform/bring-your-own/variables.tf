variable "kong_ip" {
  type = string
}

variable "kong_internal_ip" {
  type = string
  default = ""
}

variable "worker_ip" {
  type = string
}

variable "worker_internal_ip" {
  type = string
  default = ""
}

locals {
  kong_internal_ip_fallback = var.kong_internal_ip != "" ? var.kong_internal_ip : var.kong_ip
  worker_internal_ip_fallback = var.worker_internal_ip != "" ? var.worker_internal_ip : var.worker_ip
}

# db IP fallback is done in the lua part
variable "db_ip" {
  type = string
  default = ""
}

variable "db_internal_ip" {
  type = string
  default = ""
}

variable "ssh_key_path" {
  type = string
}

variable "seperate_db_node" {
  type        = bool
  description = "Whether to create a separate db instance"
  default     = false
}
