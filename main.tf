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

# EC2 Instance using Custom AMI (Remote MySQL on RDS)
resource "aws_instance" "web_app_instance" {
  ami                    = var.custom_ami
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_subnets[0].id
  vpc_security_group_ids = [aws_security_group.web_app_sg.id]
  key_name               = var.key_pair

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = var.volume_type
  }

  user_data = <<-EOF
              #!/bin/bash
              echo "DB_HOST=${aws_db_instance.rds_instance.address}" >> /etc/environment
              echo "DB_USER=${var.db_username}" >> /etc/environment
              echo "DB_PASSWORD=${var.db_password}" >> /etc/environment
              echo "DB_NAME=${var.db_name}" >> /etc/environment

              # Source the environment variables
              source /etc/environment

              # Restart the application service to apply new environment variables
              sudo systemctl restart my-app.service
              EOF

  tags = {
    Name = "${var.env}-web-app-instance"
  }
}