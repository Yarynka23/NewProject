# State lives in HCP Terraform. The organization and workspace come from TF_CLOUD_ORGANIZATION
# and TF_WORKSPACE (set in .env); the token from TF_TOKEN_app_terraform_io. The workspace uses
# local execution (infra/hcp-workspace.sh sets it up): plans and applies run on this machine,
# which has Docker, Node.js and the AWS credentials, and only the state is stored remotely.
terraform {
  required_version = ">= 1.10"

  cloud {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Every resource that supports tags is tagged PROJECT_NAME=<project_name>.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = { PROJECT_NAME = var.project_name }
  }
}

# CloudFront only accepts ACM certificates from us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = { PROJECT_NAME = var.project_name }
  }
}
