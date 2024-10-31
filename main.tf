# Terraform Configuration
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Update this to the latest version you are using
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

# Public Subnets Loop
resource "aws_subnet" "public_subnets" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = element(var.azs, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.env}-public-subnet-${count.index + 1}"
  }
}

# Private Subnets Loop (For RDS)
resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = element(var.azs, count.index)

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

# Public Route Table Associations for Public Subnets Loop
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

# Private Route Table Associations for Private Subnets Loop
resource "aws_route_table_association" "private_association" {
  count          = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security Group for Web Application
resource "aws_security_group" "web_app_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

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

  ingress {
    from_port   = var.app_port
    to_port     = var.app_port
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
    Name = "${var.env}-web-app-sg"
  }
}

# Security Group for RDS
resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_app_sg.id]
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

# RDS Parameter Group for MySQL
resource "aws_db_parameter_group" "my_db_parameter_group" {
  name        = "${var.env}-rds-parameter-group"
  family      = "mysql8.0"
  description = "Custom parameter group for MySQL RDS instance"

  parameter {
    name  = "character_set_client"
    value = "utf8"
  }

  parameter {
    name  = "character_set_server"
    value = "utf8"
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
  parameter_group_name   = aws_db_parameter_group.my_db_parameter_group.name
  skip_final_snapshot    = true
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name

  tags = {
    Name = "${var.env}-rds-instance"
  }
}

# Random ID for Bucket Name
resource "random_id" "bucket_name" {
  byte_length = 7
}

# S3 Bucket Configuration
resource "aws_s3_bucket" "private_webapp_bucket" {
  bucket = "s3-${var.env}-${random_id.bucket_name.hex}"

  force_destroy = true # Allow deletion of non-empty bucket

  tags = {
    Name        = "${var.env}-private-webapp-bucket"
    Environment = "${var.env} - S3 Bucket"
  }
}

# S3 Bucket Lifecycle Configuration (Transition to STANDARD_IA after 30 days)
resource "aws_s3_bucket_lifecycle_configuration" "s3_lifecycle_config" {
  bucket = aws_s3_bucket.private_webapp_bucket.bucket

  rule {
    id = "lifecycle"
    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    status = "Enabled"
  }
}

# Enable Default Encryption on S3 Bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "s3_key_encryption" {
  bucket = aws_s3_bucket.private_webapp_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Restrict Public Access to S3 Bucket
resource "aws_s3_bucket_public_access_block" "s3_bucket_public_access_block" {
  bucket = aws_s3_bucket.private_webapp_bucket.bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM Role for EC2 to Access S3 and CloudWatch
resource "aws_iam_role" "s3_access_role_to_ec2" {
  name = "${var.env}-S3BucketAccessRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Sid       = "RoleForEC2",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# IAM Policy for S3, CloudWatch, and CloudWatch Logs for StatsD
resource "aws_iam_policy" "s3_cloudwatch_statsd_policy" {
  name        = "${var.env}-S3CloudWatchStatsDPolicy"
  description = "Policy for EC2 to interact with S3, CloudWatch, and CloudWatch Logs for StatsD metrics and logging"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.private_webapp_bucket.bucket}/*",
          "arn:aws:s3:::${aws_s3_bucket.private_webapp_bucket.bucket}"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:DescribeAlarms"
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
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Agent Policy Data Source
data "aws_iam_policy" "cloudwatch_policy" {
  arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Attach Policies to EC2 Role
resource "aws_iam_policy_attachment" "attach_s3_cloudwatch_statsd_policy" {
  name       = "${var.env}-attach-s3-cloudwatch-statsd-policy"
  roles      = [aws_iam_role.s3_access_role_to_ec2.name]
  policy_arn = aws_iam_policy.s3_cloudwatch_statsd_policy.arn
}

resource "aws_iam_policy_attachment" "policy_role_attach_cloudwatch" {
  name       = "${var.env}-policy_role_attach_cloudwatch"
  roles      = [aws_iam_role.s3_access_role_to_ec2.name]
  policy_arn = data.aws_iam_policy.cloudwatch_policy.arn
}

# Instance Profile for EC2 Role
resource "aws_iam_instance_profile" "ec2_role_profile" {
  name = "${var.env}-ec2-role-profile"
  role = aws_iam_role.s3_access_role_to_ec2.name
}

# EC2 Instance Configuration
resource "aws_instance" "web_app_instance" {
  ami                    = var.custom_ami
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_subnets[0].id
  vpc_security_group_ids = [aws_security_group.web_app_sg.id]
  key_name               = var.key_pair
  iam_instance_profile   = aws_iam_instance_profile.ec2_role_profile.name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = var.volume_type
  }

  # Enable IMDSv2 requirement
  metadata_options {
    http_tokens   = "required" # Enforces IMDSv2
    http_endpoint = "enabled"  # Ensures the metadata endpoint is enabled
  }

  user_data = <<-EOF
              #!/bin/bash
              echo "DB_HOST=${aws_db_instance.rds_instance.address}" >> /etc/environment
              echo "DB_USER=${var.db_username}" >> /etc/environment
              echo "DB_PASSWORD=${var.db_password}" >> /etc/environment
              echo "DB_NAME=${var.db_name}" >> /etc/environment
              echo "S3_BUCKET_NAME=${aws_s3_bucket.private_webapp_bucket.bucket}" >> /etc/environment
              echo "AWS_REGION=${var.region}" >> /etc/environment
              
              # Source the environment variables
              source /etc/environment

              # Restart CloudWatch agent and StatsD to ensure they're running
              sudo systemctl restart amazon-cloudwatch-agent.service
              sudo systemctl restart statsd.service  # Restart StatsD using systemd

              # Restart the application service to apply new environment variables
              sudo systemctl restart my-app.service
              EOF

  tags = {
    Name = "${var.env}-web-app-instance"
  }
}


# Route 53 Zone Data Source
data "aws_route53_zone" "selected_zone" {
  name         = var.domain_name
  private_zone = false
}

# Route 53 A Record Mapping to EC2 Instance
resource "aws_route53_record" "server_mapping_record" {
  zone_id = data.aws_route53_zone.selected_zone.zone_id
  name    = var.domain_name
  type    = var.record_type
  ttl     = var.ttl
  records = [aws_instance.web_app_instance.public_ip]
}
