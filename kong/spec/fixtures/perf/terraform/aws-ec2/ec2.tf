resource "aws_key_pair" "perf" {
  key_name   = "key-perf-test-${random_string.ident.result}"
  public_key = tls_private_key.key.public_key_openssh
}

data "aws_ami" "perf" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.ec2_os]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_security_group" "openall" {
  ingress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_instance" "kong" {
  ami                         = data.aws_ami.perf.id
  instance_type               = var.ec2_instance_type
  key_name                    = aws_key_pair.perf.key_name
  monitoring                  = true
  security_groups              = [aws_security_group.openall.name]
  associate_public_ip_address = true

  root_block_device {
    tags                  = {
      PerfTest = "perf-${random_string.ident.result}"
      Name     = "kong-${random_string.ident.result}"
    }
    volume_size           = 100
  }

  tags = {
    PerfTest = "perf-${random_string.ident.result}"
    Name     = "kong-${random_string.ident.result}"
  }
}

resource "aws_instance" "db" {
  count                       = var.seperate_db_node ? 1: 0
  ami                         = data.aws_ami.perf.id
  instance_type               = var.ec2_instance_db_type
  key_name                    = aws_key_pair.perf.key_name
  monitoring                  = true
  security_groups              = [aws_security_group.openall.name]
  associate_public_ip_address = true

  root_block_device {
    tags                  = {
      PerfTest = "perf-${random_string.ident.result}"
      Name     = "kong-${random_string.ident.result}"
    }
    volume_size           = 100
  }

  tags = {
    PerfTest = "perf-${random_string.ident.result}"
    Name     = "db-${random_string.ident.result}"
  }
}

resource "aws_instance" "worker" {
  ami                         = data.aws_ami.perf.id
  instance_type               = var.ec2_instance_worker_type
  key_name                    = aws_key_pair.perf.key_name
  monitoring                  = true
  security_groups              = [aws_security_group.openall.name]
  associate_public_ip_address = true

  root_block_device {
    tags                  = {
      PerfTest = "perf-${random_string.ident.result}"
      Name     = "kong-${random_string.ident.result}"
    }
    volume_size           = 100
  }

  tags = {
    PerfTest = "perf-${random_string.ident.result}"
    Name     = "worker-${random_string.ident.result}"
  }
}


resource "random_string" "ident" {
  length  = 4
  special = false
}
