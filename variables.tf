# CIDR Block for VPC
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

# CIDR Blocks for Public Subnets
variable "public_subnets" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

# CIDR Blocks for Private Subnets
variable "private_subnets" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

# Availability Zones
variable "azs" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

# AWS Profile and Region
variable "aws_profile" {
  description = "AWS profile to use"
  default     = "default"
}

variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

# Application Environment (dev, demo, prod)
variable "env" {
  description = "Application environment"
  default     = "demo"
}

# Allowed SSH CIDR Blocks
variable "allowed_ssh_cidrs" {
  description = "Allowed CIDR blocks for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Replace with your actual IP for better security
}

# Custom AMI
variable "custom_ami" {
  description = "AMI ID of the custom image created by Packer"
  default     = "ami-08f1ff826dff443f8" # Replace with your custom AMI ID
}

# EC2 Instance Type
variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.small"
}

# Root Volume Configuration
variable "root_volume_size" {
  description = "Root volume size (in GB)"
  default     = 25
}

variable "volume_type" {
  description = "EBS volume type"
  default     = "gp2"
}

# Application Port
variable "app_port" {
  description = "The port where the application will run"
  default     = 8080
}

# Key Pair for EC2 SSH Access
variable "key_pair" {
  description = "Key pair name for SSH access"
  default     = "my-aws-key" # Replace with your actual key pair
}

# Database Configuration Variables
variable "db_name" {
  description = "The name of the RDS database"
}

variable "db_username" {
  description = "The username for the RDS database"
}

variable "db_password" {
  description = "The password for the RDS database"
  sensitive   = true
}

variable "db_port" {
  description = "Database port number"
  type        = number
  default     = 3306
}

# Domain Name
variable "domain_name" {
  description = "The root domain name for Route 53"
}

# Record Type for Route 53
variable "record_type" {
  description = "DNS record type for Route 53 (e.g., A, CNAME)"
  default     = "A"
}

# TTL for Route 53 record
variable "ttl" {
  description = "Time to Live (TTL) for the Route 53 record"
  type        = number
  default     = 300
}
# Auto-scaling configuration
variable "desired_capacity" {
  default     = 3
  description = "Desired number of instances in the auto-scaling group"
}

variable "max_size" {
  default     = 5
  description = "Maximum number of instances in the auto-scaling group"
}

variable "min_size" {
  default     = 3
  description = "Minimum number of instances in the auto-scaling group"
}

