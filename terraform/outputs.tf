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