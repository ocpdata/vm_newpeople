locals {
  common_tags = merge(
    {
      Project   = var.name_prefix
      ManagedBy = "terraform"
    },
    var.tags,
  )
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_security_group" "vm" {
  name        = "${var.name_prefix}-sg"
  description = "Public access for SSH and web traffic to the NewPeople VM"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-sg" })
}

resource "aws_instance" "vm" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.vm.id]
  associate_public_ip_address = false

  user_data = templatefile("${path.module}/templates/cloud-init.sh.tftpl", {
    deploy_user    = var.deploy_user
    ssh_public_key = var.ssh_public_key
  })

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(local.common_tags, { Name = var.name_prefix })
}

resource "aws_eip" "vm" {
  domain = "vpc"

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-eip" })
}

resource "aws_eip_association" "vm" {
  allocation_id = aws_eip.vm.id
  instance_id   = aws_instance.vm.id
}