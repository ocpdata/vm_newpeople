variable "aws_region" {
  description = "AWS region for the EC2 instance."
  type        = string
}

variable "name_prefix" {
  description = "Name prefix used for AWS resources."
  type        = string
  default     = "vm-newpeople"
}

variable "vpc_id" {
  description = "Target VPC ID where the EC2 instance will be created."
  type        = string
}

variable "subnet_id" {
  description = "Public subnet ID where the EC2 instance will be created."
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key that will be authorized on the VM."
  type        = string
  sensitive   = true
}

variable "instance_type" {
  description = "EC2 instance type for the application host."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 30
}

variable "deploy_user" {
  description = "Linux user that receives SSH access and performs deployments."
  type        = string
  default     = "deployer"
}

variable "tags" {
  description = "Additional tags applied to created resources."
  type        = map(string)
  default     = {}
}