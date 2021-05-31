variable "packet_auth_token" {
  type        = string
  description = "The pre-existing Packet auth token"
}

variable "packet_project_id" {
  type        = string
  description = "The pre-existing Packet project ID under which to create the devices"
}

variable "packet_plan" {
  type        = string
  description = "The Packet device plan on which to create the kong and worker devices"
  default     = "baremetal_1"
}

variable "packet_region" {
  type        = string
  description = "The Packet region in which to create the devices"
  default     = "sjc1"
}

variable "packet_os" {
  type        = string
  description = "The OS to install on the Packet devices"
  default     = "ubuntu_20_04"
}

