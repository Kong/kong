variable "do_token" {
  type        = string
  description = "The digitalocean auth token"
}

variable "do_project_name" {
  type        = string
  description = "The digitalocean project ID under which to create the droplets"
  default     = "Benchmark"
}

variable "do_size" {
  type        = string
  description = "The droplet size on which to create the kong droplet"
  default     = "c2-8vpcu-16gb"
}

variable "do_worker_size" {
  type        = string
  description = "The droplet size on which to create the worker droplet"
  default     = "s-1vcpu-1gb"
}

variable "do_db_size" {
  type        = string
  description = "The droplet size on which to create the db droplet"
  default     = "s-1vcpu-1gb"
}


variable "do_region" {
  type        = string
  description = "The digitalocean region in which to create the droplets"
  default     = "sfo3"
}

variable "do_os" {
  type        = string
  description = "The OS to install on the Metal droplets"
  default     = "ubuntu-20-04-x64"
}

variable "seperate_db_node" {
  type        = bool
  description = "Whether to create a separate db instance"
  default     = false
}


