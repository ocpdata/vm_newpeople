output "instance_id" {
  description = "EC2 instance ID for the NewPeople VM."
  value       = aws_instance.vm.id
}

output "public_ip" {
  description = "Public IP used by SSH and HTTP access."
  value       = aws_eip.vm.public_ip
}

output "public_dns" {
  description = "Public DNS name associated with the Elastic IP."
  value       = aws_eip.vm.public_dns
}

output "deploy_user" {
  description = "Linux deploy user configured on the instance."
  value       = var.deploy_user
}

output "db_host" {
  description = "RDS endpoint hostname for the MySQL instance."
  value       = aws_db_instance.mysql.address
}

output "db_port" {
  description = "RDS port for the MySQL instance."
  value       = aws_db_instance.mysql.port
}

output "db_name" {
  description = "Database name created on the RDS instance."
  value       = aws_db_instance.mysql.db_name
}