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

output "security_group_id" {
  description = "The security group ID for the web application"
  value       = aws_security_group.web_app_sg.id
}

# Output for Load Balancer
output "load_balancer_dns" {
  value       = aws_lb.app_lb.dns_name
  description = "The DNS name of the load balancer"
}

output "load_balancer_security_group_id" {
  value       = aws_security_group.lb_sg.id
  description = "The security group ID for the load balancer"
}

# Optional: Auto Scaling Group name for reference
output "auto_scaling_group_name" {
  description = "The name of the auto-scaling group for the application"
  value       = aws_autoscaling_group.app_asg.name
}
