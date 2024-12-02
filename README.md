
# Terraform AWS Infrastructure Setup modified 2

This repository contains the configuration files for setting up AWS infrastructure using Terraform. Follow the steps below to set up your environment and deploy the infrastructure.

## Prerequisites

Ensure you have the following installed on your local machine:

- [Terraform](https://www.terraform.io/downloads.html) (version 1.9.7 or later)
- AWS CLI (configured with proper credentials)
- Git
- An AWS account

## Setup Instructions

### 1. Clone the Repository

First, clone this repository to your local machine:

```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
cd YOUR_REPO_NAME
```

### 2. Configure AWS CLI

Ensure your AWS CLI is configured with the appropriate credentials. You can do this by running:

```bash
aws configure
```

Enter your **Access Key**, **Secret Key**, **Region**, and **Output Format** when prompted.

### 3. Initialize Terraform

Before deploying the infrastructure, initialize Terraform to download the necessary provider plugins:

```bash
terraform init
```

### 4. Terraform Plan

To preview the changes that Terraform will make to your AWS account, run the following command:

```bash
terraform plan
```

This will show you what resources will be created, modified, or destroyed.

### 5. Apply the Terraform Configuration

To create the infrastructure in AWS, run:

```bash
terraform apply
```

You will be prompted to confirm before Terraform makes any changes. Type `yes` to proceed.

### 6. Terraform Destroy

If you need to tear down the infrastructure, use the following command:

```bash
terraform destroy
```

This will destroy all resources created by Terraform. Again, you will be prompted to confirm before any resources are deleted.

## Variables

You can modify the default values for some parameters in the `terraform.tfvars` file or override them in the command line.

For example:

```bash
terraform apply -var="vpc_cidr=10.1.0.0/16" -var="region=us-west-2"
```

Alternatively, edit the `terraform.tfvars` file to customize the values before running `terraform apply`.

## CI/CD Integration

This project includes a GitHub Actions CI pipeline that automatically runs Terraform formatting checks and validation on every pull request to the `main` branch.

Make sure your changes pass all checks before merging.

## File Structure

- `.github/workflows/pr-check.yml`: GitHub Actions configuration for CI pipeline.
- `main.tf`: Main Terraform configuration file.
- `variables.tf`: Defines the input variables for Terraform.
- `outputs.tf`: Specifies the output values.
- `terraform.tfvars`: Contains values for the input variables.

## Import SSL Certificate into AWS ACM

aws acm import-certificate \
    --certificate fileb://path/to/your_certificate.crt \
    --certificate-chain fileb://path/to/your_certificate_chain.ca-bundle \
    --private-key fileb://path/to/your_private.key \
    --region your-aws-region

Replace the placeholders with your actual file paths and AWS region:

path/to/your_certificate.crt: Path to your SSL certificate file.
path/to/your_certificate_chain.ca-bundle: Path to your certificate chain file.
path/to/your_private.key: Path to your private key file.
your-aws-region: AWS region where you want to import the certificate (e.g., us-east-1).




