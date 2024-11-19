# Terraform Configuration
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
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.env}-public-subnet-${count.index + 1}"
  }
}

# Private Subnets (For RDS and Lambda)
resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.azs[count.index]

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

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

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

# Update Private Route Table to Include NAT Gateway
resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id

  depends_on = [aws_nat_gateway.nat_gw]
}

# Security Group for Web Application
resource "aws_security_group" "web_app_sg" {
  name   = "${var.env}-web-app-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  ingress {
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
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

  # No ingress rules needed unless Lambda needs to receive inbound traffic

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

# Security Group for RDS (Updated to allow Lambda access)
resource "aws_security_group" "rds_sg" {
  name   = "${var.env}-rds-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.web_app_sg.id, aws_security_group.lambda_sg.id]

    description = "Allow MySQL access from Web App and Lambda"
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
  password               = var.db_password
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  publicly_accessible    = false
  skip_final_snapshot    = true

  tags = {
    Name = "${var.env}-rds-instance"
  }
}

# IAM Role for EC2 to Access S3, CloudWatch, and SNS Publish
resource "aws_iam_role" "s3_access_role_to_ec2" {
  name = "${var.env}-S3BucketAccessRole"

  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [{
      Effect : "Allow",
      Principal : { Service : "ec2.amazonaws.com" },
      Action : "sts:AssumeRole"
    }]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_role_profile" {
  name = "${var.env}-ec2-role-profile"
  role = aws_iam_role.s3_access_role_to_ec2.name
}

# IAM Policy for S3, CloudWatch, and CloudWatch Logs for StatsD
resource "aws_iam_policy" "s3_cloudwatch_statsd_policy" {
  name        = "${var.env}-S3CloudWatchStatsDPolicy"
  description = "Policy for EC2 to interact with S3, CloudWatch, and CloudWatch Logs for StatsD metrics and logging"

  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Effect : "Allow",
        Action : ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
        Resource : [
          "arn:aws:s3:::${aws_s3_bucket.private_webapp_bucket.bucket}/*",
          "arn:aws:s3:::${aws_s3_bucket.private_webapp_bucket.bucket}"
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
      }
    ]
  })
}

# SNS Publish Policy for EC2 Role
resource "aws_iam_role_policy" "ec2_sns_publish_policy" {
  name = "${var.env}-sns-publish-policy"
  role = aws_iam_role.s3_access_role_to_ec2.name
  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Effect : "Allow",
        Action : "sns:Publish",
        Resource : "${aws_sns_topic.user_signup_topic.arn}"
      }
    ]
  })
}

# Attach Policy to IAM Role
resource "aws_iam_policy_attachment" "attach_s3_cloudwatch_statsd_policy" {
  name       = "${var.env}-attach-s3-cloudwatch-statsd-policy"
  roles      = [aws_iam_role.s3_access_role_to_ec2.name]
  policy_arn = aws_iam_policy.s3_cloudwatch_statsd_policy.arn
}

# CloudWatch Agent Policy Data Source
data "aws_iam_policy" "cloudwatch_policy" {
  arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Attach CloudWatch Agent Policy to IAM Role
resource "aws_iam_policy_attachment" "policy_role_attach_cloudwatch" {
  name       = "${var.env}-policy_role_attach_cloudwatch"
  roles      = [aws_iam_role.s3_access_role_to_ec2.name]
  policy_arn = data.aws_iam_policy.cloudwatch_policy.arn
}

# Random ID for Bucket Name
resource "random_id" "bucket_name" {
  byte_length = 7
}

# S3 Bucket Configuration
resource "aws_s3_bucket" "private_webapp_bucket" {
  bucket        = "s3-${var.env}-${random_id.bucket_name.hex}"
  force_destroy = true

  tags = {
    Name        = "${var.env}-private-webapp-bucket"
    Environment = "${var.env} - S3 Bucket"
  }
}

# Random ID for Lambda Bucket Name
resource "random_id" "lambda_bucket_name" {
  byte_length = 7
}

# S3 Bucket for Lambda Function Code
resource "aws_s3_bucket" "lambda_code_bucket" {
  bucket        = "lambda-code-bucket-${random_id.lambda_bucket_name.hex}"
  force_destroy = true

  tags = {
    Name = "${var.env}-lambda-code-bucket"
  }
}

# S3 Object for Lambda Function Code (Using Absolute Path)
resource "aws_s3_object" "lambda_code" {
  bucket = aws_s3_bucket.lambda_code_bucket.id
  key    = local.lambda_s3_key
  source = "C:/Users/aayus/OneDrive/Desktop/serverless/emailVerification.zip"
  #etag   = filemd5("C:/Users/aayus/OneDrive/Desktop/serverless/emailVerification.zip")
}

# Security Group for ALB
resource "aws_security_group" "lb_sg" {
  name   = "${var.env}-lb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
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
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.env}-app-tg"
  }
}

# Listener for ALB on port 80
resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# Launch Template
resource "aws_launch_template" "app_launch_template" {
  name          = "${var.env}-launch-template"
  image_id      = var.custom_ami
  instance_type = var.instance_type
  key_name      = var.key_pair

  vpc_security_group_ids = [aws_security_group.web_app_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_role_profile.name
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo "DB_HOST=${aws_db_instance.rds_instance.address}" >> /etc/environment
    echo "DB_USER=${var.db_username}" >> /etc/environment
    echo "DB_PASSWORD=${var.db_password}" >> /etc/environment
    echo "DB_NAME=${var.db_name}" >> /etc/environment
    echo "S3_BUCKET_NAME=${aws_s3_bucket.private_webapp_bucket.bucket}" >> /etc/environment
    echo "AWS_REGION=${var.region}" >> /etc/environment
    echo "SNS_TOPIC_ARN=${aws_sns_topic.user_signup_topic.arn}" >> /etc/environment

    source /etc/environment
    sudo systemctl restart amazon-cloudwatch-agent.service
    sudo systemctl restart statsd.service  # Restart StatsD using systemd
    sudo systemctl restart my-app.service
    EOF
  )
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app_asg" {
  name                      = "${var.env}-app-asg"
  desired_capacity          = var.desired_capacity
  max_size                  = var.max_size
  min_size                  = var.min_size
  vpc_zone_identifier       = aws_subnet.public_subnets[*].id
  target_group_arns         = [aws_lb_target_group.app_tg.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.app_launch_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.env}-web-app-instance"
    propagate_at_launch = true
  }
}

# Scaling Policies
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up-policy"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 60
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale-down-policy"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 60
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
}

# CloudWatch Alarms for Auto Scaling
resource "aws_cloudwatch_metric_alarm" "high_cpu_alarm" {
  alarm_name          = "${var.env}-high-cpu-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 12
  alarm_description   = "This metric monitors EC2 CPU utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "low_cpu_alarm" {
  alarm_name          = "${var.env}-low-cpu-alarm"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 8
  alarm_description   = "This metric monitors EC2 CPU utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_asg.name
  }
}

# Route 53 Record
data "aws_route53_zone" "selected_zone" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_route53_record" "app_record" {
  zone_id = data.aws_route53_zone.selected_zone.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.app_lb.dns_name
    zone_id                = aws_lb.app_lb.zone_id
    evaluate_target_health = true
  }
}

# SNS Topic for user signup
resource "aws_sns_topic" "user_signup_topic" {
  name = "${var.env}-user-signup-topic"
}

# IAM Role for Lambda (Single Definition)
resource "aws_iam_role" "lambda_role" {
  name = "${var.env}-lambda-role"

  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [{
      Effect : "Allow",
      Principal : { Service : "lambda.amazonaws.com" },
      Action : "sts:AssumeRole"
    }]
  })
}

# IAM Policy for Lambda to access SES, SNS, Logs, and manage ENIs for VPC access
resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.env}-lambda-policy"
  description = "Policy for Lambda to access SES, SNS, Logs, and manage ENIs for VPC access"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        # Use wildcard to allow access to all Lambda log groups
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*"
      },
      {
        Effect   = "Allow",
        Action   = "sns:Publish",
        Resource = "${aws_sns_topic.user_signup_topic.arn}"
      },
      # EC2 permissions for VPC access
      {
        Effect = "Allow",
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ],
        Resource = "*"
      }
    ]
  })
}

# Attach the Lambda Policy to the Role
resource "aws_iam_policy_attachment" "lambda_policy_attachment" {
  name       = "${var.env}-lambda-policy-attachment"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Attach AWS Managed Policy for Lambda VPC Access
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Local Variables
locals {
  lambda_s3_key = "emailVerification.zip"
}

# Lambda Function for email verification
resource "aws_lambda_function" "email_verification_lambda" {
  function_name = "${var.env}-email-verification-lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "emailVerification.handler" # Update according to your Lambda handler
  runtime       = "nodejs18.x"                # Adjust runtime as needed
  timeout       = 30

  # Reference the S3 bucket and key for Lambda code
  s3_bucket        = aws_s3_bucket.lambda_code_bucket.id
  s3_key           = aws_s3_object.lambda_code.key
  #source_code_hash = filebase64sha256("C:/Users/aayus/OneDrive/Desktop/serverless/emailVerification.zip")

  environment {
    variables = {
      DB_HOST          = aws_db_instance.rds_instance.address
      DB_NAME          = var.db_name
      DB_USER          = var.db_username
      DB_PASSWORD      = var.db_password
      SENDGRID_API_KEY = var.sendgrid_api_key
      BASE_URL         = var.baseURL
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
    aws_iam_policy_attachment.lambda_policy_attachment,
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

  depends_on = [aws_sns_topic.user_signup_topic, aws_lambda_function.email_verification_lambda]
}
