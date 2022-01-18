variable "metal_auth_token" {
  type        = string
  description = "The pre-existing Metal auth token"
}

variable "metal_project_id" {
  type        = string
  description = "The pre-existing Metal project ID under which to create the devices"
}

variable "metal_plan" {
  type        = string
  description = "The Metal device plan on which to create the kong and worker devices"
  default     = "baremetal_1"
}

variable "metal_region" {
  type        = string
  description = "The Metal region in which to create the devices"
  default     = "sjc1"
}

variable "metal_os" {
  type        = string
  description = "The OS to install on the Metal devices"
  default     = "ubuntu_20_04"
}

