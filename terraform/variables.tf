variable "aws_region" {
  description = "AWS region for the EC2 instance."
  type        = string
}

variable "name_prefix" {
  description = "Name prefix used for AWS resources."
  type        = string
  default     = "vm-newpeople"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the NewPeople VPC."
  type        = string
}

variable "public_subnet_cidr" {
  description = "IPv4 CIDR block for the public EC2 subnet."
  type        = string
}

variable "private_subnet_1_cidr" {
  description = "IPv4 CIDR block for the first private RDS subnet."
  type        = string
}

variable "private_subnet_2_cidr" {
  description = "IPv4 CIDR block for the second private RDS subnet."
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

variable "db_instance_class" {
  description = "RDS instance class for MySQL."
  type        = string
}

variable "db_allocated_storage" {
  description = "Allocated storage for the RDS instance in GiB."
  type        = number
}

variable "db_engine_version" {
  description = "MySQL engine version for the RDS instance."
  type        = string
}

variable "db_name" {
  description = "Initial database name created on the RDS instance."
  type        = string
}

variable "db_port" {
  description = "Port exposed by the RDS MySQL instance."
  type        = number
}

variable "db_username" {
  description = "Master username for the RDS MySQL instance."
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Master password for the RDS MySQL instance."
  type        = string
  sensitive   = true
}

variable "db_multi_az" {
  description = "Whether to deploy the RDS instance in Multi-AZ mode."
  type        = bool
}

variable "db_publicly_accessible" {
  description = "Whether the RDS instance should have a public endpoint."
  type        = bool
}

variable "db_deletion_protection" {
  description = "Whether to enable deletion protection on the RDS instance."
  type        = bool
}

variable "db_skip_final_snapshot" {
  description = "Whether terraform destroy should skip taking a final snapshot."
  type        = bool
}