variable "aws_region" {
  type        = string
  description = "The EC2 region in which to create the EC2 instances"
  default     = "us-east-2"
}

variable "ec2_instance_type" {
  type        = string
  description = "The EC2 size on which to run the kong, db and worker"
  default     = "c4.4xlarge"
}

variable "ec2_os" {
  type        = string
  description = "The OS to install on the EC2"
  default     = "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"
}

