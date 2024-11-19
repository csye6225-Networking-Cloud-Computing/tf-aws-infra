# VPC and Subnets
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnets" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

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

# Environment Configuration
variable "env" {
  description = "Application environment"
  default     = "demo"
}

# Security Configuration
variable "allowed_ssh_cidrs" {
  description = "Allowed CIDR blocks for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Replace with a specific IP for better security
}

# EC2 and AMI Configuration
variable "custom_ami" {
  description = "AMI ID of the custom image created by Packer"
  default     = "ami-08f1ff826dff443f8" # Replace with your custom AMI ID
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.small"
}

variable "root_volume_size" {
  description = "Root volume size (in GB)"
  default     = 25
}

variable "volume_type" {
  description = "EBS volume type"
  default     = "gp2"
}

variable "app_port" {
  description = "The port where the application will run"
  default     = 8080
}

variable "key_pair" {
  description = "Key pair name for SSH access"
  default     = "my-aws-key" # Replace with your actual key pair
}

# Database Configuration
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

# Domain and Route 53
variable "domain_name" {
  description = "The root domain name for Route 53"
}

variable "subdomain" {
  description = "Subdomain for the application (e.g., www, app)"
  type        = string
  default     = "www"
}

variable "record_type" {
  description = "DNS record type for Route 53 (e.g., A, CNAME)"
  default     = "A"
}

variable "ttl" {
  description = "Time to Live (TTL) for the Route 53 record"
  type        = number
  default     = 300
}

# Auto-scaling Configuration
variable "desired_capacity" {
  description = "Desired number of instances in the auto-scaling group"
  default     = 3
}

variable "max_size" {
  description = "Maximum number of instances in the auto-scaling group"
  default     = 5
}

variable "min_size" {
  description = "Minimum number of instances in the auto-scaling group"
  default     = 3
}

# SNS Topic and Lambda Configuration
variable "sns_topic_name" {
  description = "Name for the SNS topic for user account creation notifications"
  default     = "user-account-creation"
}

variable "lambda_function_name" {
  description = "Name for the Lambda function handling email verification"
  default     = "emailVerificationLambda"
}

variable "email_sender" {
  description = "Email address to send verification emails from"
  default     = "noreply@example.com" # Replace with your actual sender email
}

variable "lambda_role_name" {
  description = "Name for the IAM role assigned to Lambda function"
  default     = "LambdaExecutionRole"
}

# SendGrid API Key
variable "sendgrid_api_key" {
  description = "API Key for SendGrid to send emails"
  sensitive   = true
}

variable "baseURL" {
  description = "The base URL for the activation link in the Lambda function."
  type        = string
}

# Optional: NAT Gateway Count for High Availability
variable "nat_gateway_count" {
  description = "Number of NAT Gateways to deploy for high availability"
  type        = number
  default     = 1
}

# Optional: Reserved Concurrency for Lambda
variable "lambda_reserved_concurrent_executions" {
  description = "Reserved concurrent executions for the Lambda function to manage database connections"
  type        = number
  default     = 10
}
