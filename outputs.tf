output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "The IDs of the public subnets"
  value       = aws_subnet.public_subnets[*].id
}

output "private_subnet_ids" {
  description = "The IDs of the private subnets"
  value       = aws_subnet.private_subnets[*].id
}

output "internet_gateway_id" {
  description = "The ID of the internet gateway"
  value       = aws_internet_gateway.main.id
}

output "instance_public_ip" {
  description = "The public IP of the web application instance"
  value       = aws_instance.web_app_instance.public_ip
}

output "instance_id" {
  description = "The ID of the EC2 instance"
  value       = aws_instance.web_app_instance.id
}

output "security_group_id" {
  description = "The security group ID"
  value       = aws_security_group.web_app_sg.id
}
