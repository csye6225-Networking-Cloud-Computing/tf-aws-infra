terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Provider Configuration
provider "aws" {
  profile = var.aws_profile
  region  = var.region
}

# Data Source to Retrieve AWS Account ID
data "aws_caller_identity" "current" {}

# Data Sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_route53_zone" "selected_zone" {
  name         = var.domain_name
  private_zone = false
}

# Generate Random String for S3 Bucket Name
resource "random_string" "s3_bucket_name" {
  upper   = false
  lower   = true
  special = false
  length  = 5
}

# Generate Random Password for RDS
resource "random_password" "db_password" {
  length      = 16
  special     = false # Do not include special characters
  min_upper   = 1     # Ensure at least one uppercase letter
  min_lower   = 1     # Ensure at least one lowercase letter
  min_numeric = 1     # Ensure at least one numeric character
}

# KMS Keys

## KMS Key for EC2 (EBS Volumes)
resource "aws_kms_key" "ebs_kms_key" {
  description             = "KMS key for EBS encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  rotation_period_in_days = 90

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Id" : "key-policy-ec2-ebs",
    "Statement" : [
      {
        "Sid" : "Enable IAM User Permissions",
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        "Action" : "kms:*",
        "Resource" : "*"
      },
      {
        "Sid" : "Allow Auto Scaling Service to Use the Key",
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
        },
        "Action" : [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion",
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "Allow Attachment of Persistent Resources",
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
        },
        "Action" : [
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ],
        "Resource" : "*",
        "Condition" : {
          "Bool" : {
            "kms:GrantIsForAWSResource" : "true"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.env}-ebs-kms-key"
  }
}

## KMS Key for RDS
resource "aws_kms_key" "rds_kms_key" {
  description             = "KMS key for RDS encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  rotation_period_in_days = 90

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Id": "key-for-rds",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow use of the key for RDS",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
EOF

  tags = {
    Name = "${var.env}-rds-kms-key"
  }
}

## KMS Key for S3
resource "aws_kms_key" "s3_kms_key" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  rotation_period_in_days = 90

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Id": "key-for-s3",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow use of the key for S3",
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
EOF

  tags = {
    Name = "${var.env}-s3-kms-key"
  }
}

## KMS Key for Secrets Manager
resource "aws_kms_key" "secrets_kms_key" {
  description             = "KMS key for Secrets Manager"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  rotation_period_in_days = 90

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Id": "key-for-secrets-manager",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow use of the key for Secrets Manager",
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
EOF

  tags = {
    Name = "${var.env}-secrets-kms-key"
  }
}

# Store DB Password in Secrets Manager
# Create the Secrets Manager Secret
# Create the Secrets Manager Secret with Lifecycle Rules
resource "aws_secretsmanager_secret" "db_password_secret" {
  name        = "demo-db-password"
  description = "Database password for RDS instance"

  lifecycle {
    create_before_destroy = true
  }
}

# Use a Null Resource for Timing Delays
resource "null_resource" "delay_for_secret" {
  provisioner "local-exec" {
    command = "powershell -Command Start-Sleep -Seconds 10"
  }

  depends_on = [aws_secretsmanager_secret_version.db_password_secret_version]
}

resource "aws_secretsmanager_secret_version" "db_password_secret_version" {
  secret_id = aws_secretsmanager_secret.db_password_secret.id
  secret_string = random_password.db_password.result
}

# Data Block to Read the Secret Version
data "aws_secretsmanager_secret_version" "db_password_secret_version" {
  secret_id = aws_secretsmanager_secret.db_password_secret.id

  depends_on = [null_resource.delay_for_secret]
}

# Gracefully Handle Errors with try
locals {
  db_password_secret_version = try(data.aws_secretsmanager_secret_version.db_password_secret_version.secret_string, null)
}


# Optional resource to demonstrate handling
resource "null_resource" "conditional_reference" {
  provisioner "local-exec" {
    command = <<EOT
    echo "Secret string is: ${local.db_password_secret_version != null ? local.db_password_secret_version : "Not available yet"}"
    EOT
  }
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.env}-main-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.env}-main-igw"
  }
}

# Public Subnets
resource "aws_subnet" "public_subnets" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.azs[count.index % length(var.azs)]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.env}-public-subnet-${count.index + 1}"
  }
}

# Private Subnets
resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.azs[count.index % length(var.azs)]

  tags = {
    Name = "${var.env}-private-subnet-${count.index + 1}"
  }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.env}-public-route-table"
  }
}

# Public Route Table Associations for Public Subnets
resource "aws_route_table_association" "public_association" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway Elastic IP
resource "aws_eip" "nat_eip" {
  vpc = true

  tags = {
    Name = "${var.env}-nat-eip"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnets[0].id

  tags = {
    Name = "${var.env}-nat-gateway"
  }
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = {
    Name = "${var.env}-private-route-table"
  }
}

# Private Route Table Associations for Private Subnets
resource "aws_route_table_association" "private_association" {
  count          = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security Group for Web Application (Removed SSH Access)
resource "aws_security_group" "web_app_sg" {
  name   = "${var.env}-web-app-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Temporary SSH access from my IP"
  }


  # New rule allowing traffic from within the VPC
  ingress {
    description = "Allow HTTP traffic from VPC"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.env}-web-app-sg"
  }
}

# Security Group for Lambda
resource "aws_security_group" "lambda_sg" {
  name        = "${var.env}-lambda-sg"
  description = "Security group for Lambda functions"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.env}-lambda-sg"
  }
}

# Security Group for RDS
resource "aws_security_group" "rds_sg" {
  name   = "${var.env}-rds-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.web_app_sg.id, aws_security_group.lambda_sg.id]
    description     = "Allow DB access from Web App and Lambda"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.env}-rds-sg"
  }
}

# DB Subnet Group for RDS (Private Subnets)
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "${var.env}-rds-subnet-group"
  subnet_ids = aws_subnet.private_subnets[*].id

  tags = {
    Name = "${var.env}-rds-subnet-group"
  }
}

# RDS Instance
resource "aws_db_instance" "rds_instance" {
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = var.db_name
  username               = var.db_username
  password               = random_password.db_password.result
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  publicly_accessible    = false
  skip_final_snapshot    = true
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.rds_kms_key.arn

  tags = {
    Name = "${var.env}-rds-instance"
  }
}

# S3 Bucket Configuration
resource "aws_s3_bucket" "aws_s3_bucket" {
  bucket        = "s3-${var.env}-${random_string.s3_bucket_name.result}"
  force_destroy = true

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = aws_kms_key.s3_kms_key.arn
      }
    }
  }

  versioning {
    enabled = true
  }

  lifecycle_rule {
    id      = "lifecycle"
    enabled = true

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }

  tags = {
    Name        = "${var.env}-private-webapp-bucket"
    Environment = "${var.env} - S3 Bucket"
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "s3_bucket_public_access_block" {
  bucket = aws_s3_bucket.aws_s3_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM Role for EC2 Instance
resource "aws_iam_role" "ec2_role" {
  name = "${var.env}-ec2-role"

  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Effect : "Allow",
        Principal : { Service : "ec2.amazonaws.com" },
        Action : "sts:AssumeRole"
      }
    ]
  })
}

# IAM Policy for EC2 Role
resource "aws_iam_policy" "ec2_policy" {
  name        = "${var.env}-ec2-policy"
  description = "Policy for EC2 to access S3, CloudWatch, SNS, and Secrets Manager"

  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Effect : "Allow",
        Action : ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
        Resource : [
          "arn:aws:s3:::${aws_s3_bucket.aws_s3_bucket.id}",
          "arn:aws:s3:::${aws_s3_bucket.aws_s3_bucket.id}/*"
        ]
      },
      {
        Effect : "Allow",
        Action : [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:DescribeAlarms"
        ],
        Resource : "*"
      },
      {
        Effect : "Allow",
        Action : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource : "*"
      },
      {
        Effect : "Allow",
        Action : ["sns:Publish"],
        Resource : "${aws_sns_topic.user_signup_topic.arn}"
      },
      {
        Effect : "Allow",
        Action : ["secretsmanager:GetSecretValue"],
        Resource : "${aws_secretsmanager_secret.db_password_secret.arn}"
      }
    ]
  })
}

# Attach Policy to EC2 Role
resource "aws_iam_role_policy_attachment" "ec2_role_policy_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_policy.arn
}

# CloudWatch Agent Policy Attachment
data "aws_iam_policy" "cloudwatch_policy" {
  name = "CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "ec2_role_cloudwatch_policy_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = data.aws_iam_policy.cloudwatch_policy.arn
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_role_profile" {
  name = "${var.env}-ec2-role-profile"
  role = aws_iam_role.ec2_role.name
}

# Load Balancer Security Group
resource "aws_security_group" "lb_sg" {
  name        = "${var.env}-lb-sg"
  description = "Security group for load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.env}-lb-sg"
  }
}

# Application Load Balancer
resource "aws_lb" "app_lb" {
  name               = "${var.env}-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = aws_subnet.public_subnets[*].id

  tags = {
    Name = "${var.env}-app-lb"
  }
}

# Target Group
resource "aws_lb_target_group" "app_tg" {
  name     = "${var.env}-app-tg"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    interval            = 30
    path                = "/healthz"
    protocol            = "HTTP"
    port                = "traffic-port"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name = "${var.env}-app-tg"
  }
}

# Listener for ALB on port 443 (HTTPS)
resource "aws_lb_listener" "app_listener_https" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.demo_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# Route 53 Record
resource "aws_route53_record" "app_record" {
  zone_id = data.aws_route53_zone.selected_zone.zone_id
  name    = var.domain_name
  type    = var.record_type

  alias {
    name                   = aws_lb.app_lb.dns_name
    zone_id                = aws_lb.app_lb.zone_id
    evaluate_target_health = true
  }
}

# Generate random strings for uniqueness
resource "random_string" "launch_template_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "random_string" "secret_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Launch Template
resource "aws_launch_template" "lt" {
  name          = "${var.env}-launch-template-${random_string.launch_template_suffix.result}"
  image_id      = var.custom_ami
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_role_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web_app_sg.id]
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      delete_on_termination = true
      volume_size           = var.root_volume_size
      volume_type           = var.volume_type
      encrypted             = true
      kms_key_id            = aws_kms_key.ebs_kms_key.arn
    }
  }
  user_data = base64encode(<<-EOF
#!/bin/bash

# Debugging logs for troubleshooting
exec >> /var/log/user_data.log 2>&1
echo "Starting user data script"

# Writing environment variables to /etc/environment
echo "Writing environment variables to /etc/environment"
cat <<EOT >> /etc/environment
DB_HOST=${aws_db_instance.rds_instance.address}
DB_PASSWORD=${jsonencode(data.aws_secretsmanager_secret_version.db_password_secret_version.secret_string)}
DB_NAME=${var.db_name}
DB_USER=${var.db_username}
S3_BUCKET_NAME=${aws_s3_bucket.aws_s3_bucket.bucket}
AWS_REGION=${var.region}
SNS_TOPIC_ARN=${aws_sns_topic.user_signup_topic.arn}
EOT

# Source environment variables
source /etc/environment

# Restart services
echo "Restarting services"
sudo systemctl restart amazon-cloudwatch-agent.service
sudo systemctl restart statsd.service
sudo systemctl restart my-app.service

echo "User data script completed"
EOF
)
}
# Auto Scaling Group
resource "aws_autoscaling_group" "asg" {
  name                      = "${var.env}-asg"
  desired_capacity          = var.desired_capacity
  max_size                  = var.max_size
  min_size                  = var.min_size
  vpc_zone_identifier       = aws_subnet.public_subnets[*].id
  target_group_arns         = [aws_lb_target_group.app_tg.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.env}-asg-instance"
    propagate_at_launch = true
  }
}

# Scaling Policies
resource "aws_autoscaling_policy" "scale_up_policy" {
  name                   = "instance-scale-up-policy"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 60
  autoscaling_group_name = aws_autoscaling_group.asg.name
}

resource "aws_autoscaling_policy" "scale_down_policy" {
  name                   = "instance-scale-down-policy"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 60
  autoscaling_group_name = aws_autoscaling_group.asg.name
}

# CloudWatch Alarms for Auto Scaling
resource "aws_cloudwatch_metric_alarm" "scale_up_policy_alarm" {
  alarm_name          = "${var.env}-high-cpu-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 12
  alarm_description   = "This metric monitors EC2 CPU utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_up_policy.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "scale_down_policy_alarm" {
  alarm_name          = "${var.env}-low-cpu-alarm"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 8
  alarm_description   = "This metric monitors EC2 CPU utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_down_policy.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg.name
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "aws_cloudwatch_log_group_csye6225" {
  name = "/aws/lambda/${var.lambda_function_name}"
}

# SNS Topic for User Signup
resource "aws_sns_topic" "user_signup_topic" {
  name = var.sns_topic_name
}

# Store Email Service Credentials in Secrets Manager
# Secrets Manager Secret
resource "aws_secretsmanager_secret" "email_service_credentials" {
  name        = "${var.env}-email-service-credentials-${random_string.secret_suffix.result}"
  description = "Email service credentials for Lambda function"
  kms_key_id  = aws_kms_key.secrets_kms_key.arn

  tags = {
    Name = "${var.env}-email-service-credentials-secret"
  }
}
resource "aws_secretsmanager_secret_version" "email_service_credentials_version" {
  secret_id = aws_secretsmanager_secret.email_service_credentials.id
  secret_string = jsonencode({
    sendgrid_api_key = var.sendgrid_api_key
  })
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = var.lambda_role_name

  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Effect : "Allow",
        Principal : { Service : "lambda.amazonaws.com" },
        Action : "sts:AssumeRole"
      }
    ]
  })
}

# IAM Policy for Lambda
resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.env}-lambda-policy"
  description = "Policy for Lambda to access required services"

  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Effect : "Allow",
        Action : [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ],
        Resource : "*"
      },
      {
        Effect : "Allow",
        Action : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource : "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*"
      },
      {
        Effect : "Allow",
        Action : "sns:Publish",
        Resource : "${aws_sns_topic.user_signup_topic.arn}"
      },
      {
        Effect : "Allow",
        Action : [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ],
        Resource : "*"
      },
      {
        Effect : "Allow",
        Action : ["secretsmanager:GetSecretValue"],
        Resource : [
          "${aws_secretsmanager_secret.email_service_credentials.arn}",
          "${aws_secretsmanager_secret.db_password_secret.arn}"
        ]
      }
    ]
  })
}

# Attach Policy to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda_role_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Attach AWS Managed Policy for Lambda VPC Access
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# S3 Bucket for Lambda Function Code
resource "aws_s3_bucket" "lambda_code_bucket" {
  bucket        = "lambda-code-bucket-${random_string.s3_bucket_name.result}"
  force_destroy = true

  tags = {
    Name = "${var.env}-lambda-code-bucket"
  }
}

# S3 Object for Lambda Function Code
resource "aws_s3_object" "lambda_code" {
  bucket = aws_s3_bucket.lambda_code_bucket.id
  key    = "emailVerification.zip"
  source = "C:/Users/aayus/OneDrive/Desktop/Aayushi_Choksi_002812272_08/serverless/emailVerification.zip" # Update the path accordingly
  #etag   = filemd5("C:/Users/aayus/OneDrive/Desktop/Aayushi_Choksi_002812272_08/serverless/emailVerification.zip")
}

# Lambda Function for Email Verification
resource "aws_lambda_function" "email_verification_lambda" {
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_role.arn
  handler       = "emailVerification.handler"
  runtime       = "nodejs18.x"
  timeout       = 30

  s3_bucket = aws_s3_bucket.lambda_code_bucket.id
  s3_key    = aws_s3_object.lambda_code.key

  environment {
  variables = {
    DB_HOST                       = aws_db_instance.rds_instance.address
    DB_NAME                       = var.db_name
    DB_USER                       = var.db_username
    BASE_URL                      = var.baseURL
    EMAIL_CREDENTIALS_SECRET_NAME = aws_secretsmanager_secret.email_service_credentials.name
    REGION                        = var.region
    SECRET_ID                     = aws_secretsmanager_secret.db_password_secret.id
    DB_CREDENTIALS_SECRET_NAME    = aws_secretsmanager_secret.db_password_secret.name
  }
}
  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  tags = {
    Name = "${var.env}-email-verification-lambda"
  }

  depends_on = [
    aws_s3_object.lambda_code,
    aws_iam_role_policy_attachment.lambda_role_policy_attachment,
    aws_iam_role_policy_attachment.lambda_vpc_access
  ]
}

# SNS Topic Subscription to Lambda
resource "aws_sns_topic_subscription" "lambda_subscription" {
  topic_arn = aws_sns_topic.user_signup_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.email_verification_lambda.arn
}

# Lambda Permission to Allow SNS Invocation
resource "aws_lambda_permission" "allow_sns_invoke" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.email_verification_lambda.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.user_signup_topic.arn
}