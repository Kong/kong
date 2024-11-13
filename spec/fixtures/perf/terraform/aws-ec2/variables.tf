variable "aws_region" {
  type        = string
  description = "The EC2 region in which to create the EC2 instances"
  default     = "us-east-2"
}

variable "ec2_instance_type" {
  type        = string
  description = "The EC2 size on which to run the kong"
  default     = "c5a.2xlarge"
}

variable "ec2_instance_worker_type" {
  type        = string
  description = "The EC2 size on which to run the worker"
  default     = "c5a.large"
}

variable "ec2_instance_db_type" {
  type        = string
  description = "The EC2 size on which to run the db"
  default     = "c5a.large"
}

variable "ec2_os" {
  type        = string
  description = "The OS to install on the EC2"
  default     = "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"
}

variable "seperate_db_node" {
  type        = bool
  description = "Whether to create a separate db instance"
  default     = false
}

