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
  description = "The Metal device plan on which to create the kong devices"
  default     = "c3.small.x86"
}

variable "metal_worker_plan" {
  type        = string
  description = "The Metal device plan on which to create the worker devices"
  default     = "c3.small.x86"
}

variable "metal_db_plan" {
  type        = string
  description = "The Metal device plan on which to create the db devices"
  default     = "c3.small.x86"
}

variable "metal_region" {
  type        = list(string)
  description = "The Metal region in which to create the devices"
  # All AMER facilities
  default     = ["dc13", "da11", "sv15", "sv16", "sp4", "ch3", "ny5", "ny7", "la4", "tr2", "se4"]
}

variable "metal_os" {
  type        = string
  description = "The OS to install on the Metal devices"
  default     = "ubuntu_20_04"
}

variable "seperate_db_node" {
  type        = bool
  description = "Whether to create a separate db instance"
  default     = false
}


