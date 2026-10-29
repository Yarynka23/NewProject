# Backend API on AWS Lambda (container image + Lambda Web Adapter) and its PostgreSQL database
# on Aurora Serverless v2 (0-1 ACU, pauses when idle). The function runs in the database's
# private subnets and needs no internet access, so there is no NAT gateway.

terraform {
  required_providers {
    aws    = { source = "hashicorp/aws" }
    http   = { source = "hashicorp/http" }
    random = { source = "hashicorp/random" }
  }
}

variable "project_name" {
  type = string
}

variable "memory_size" {
  type        = number
  default     = 512
  description = "Lambda memory in MB (CPU scales with it)."
}

variable "cors_origins" {
  type        = list(string)
  description = "Origins allowed to call the API."
}

variable "cognito_issuer" {
  type = string
}

variable "cognito_pool_id" {
  type        = string
  description = "User pool whose ID tokens the API accepts."
}

variable "cognito_client_id" {
  type        = string
  description = "App client the tokens must be issued to."
}

locals {
  db_name = "meetings"
  db_user = "meetings"

  # The image is tagged with a hash of what goes into it, so it is rebuilt (ECR tags are
  # immutable) exactly when the backend changes.
  backend_dir = "${path.root}/../backend"
  image_tag = substr(sha1(join("", [
    for f in sort(setunion(
      fileset(local.backend_dir, "{Dockerfile,pyproject.toml,uv.lock,alembic.ini}"),
      fileset(local.backend_dir, "{app,alembic}/**/*.{py,mako}"),
    )) :
    "${f}:${filesha1("${local.backend_dir}/${f}")}"
  ])), 0, 12)
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# ----------------------------------------------------------------- Network
# Private subnets only: the function talks to nothing but the database.
resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.project_name }
}

# Two availability zones: required by RDS subnet groups, and keeps Lambda highly available.
resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.${10 + count.index}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "${var.project_name}-private-${["a", "b"][count.index]}" }
}

# --------------------------------------------------------- Security groups
resource "aws_security_group" "function" {
  name_prefix = "${var.project_name}-function-"
  description = "Backend Lambda function (outbound only)"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_egress_rule" "function_all" {
  security_group_id = aws_security_group.function.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "database" {
  name_prefix = "${var.project_name}-database-"
  description = "PostgreSQL, reachable only from the backend function"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "database_from_function" {
  security_group_id            = aws_security_group.database.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.function.id
}

# ---------------------------------------------------------------- Database
# Hex only, so it can go into DATABASE_URL without escaping.
resource "random_id" "db_password" {
  byte_length = 24
}

resource "aws_db_subnet_group" "this" {
  name        = "${var.project_name}-db"
  description = "Private subnets for the backend database"
  subnet_ids  = aws_subnet.private[*].id
}

# Keeps the final snapshot names of successive destroys apart.
resource "random_id" "final_snapshot" {
  byte_length = 4
}

resource "aws_rds_cluster" "this" {
  cluster_identifier = "${var.project_name}-db"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = "17.11"

  # Serverless v2 between 0 and 1 ACU (1 ACU is about 2 GB of memory). After 5 idle minutes
  # it pauses (billed for storage only) and resumes in about 15 seconds on the next connection.
  serverlessv2_scaling_configuration {
    min_capacity             = 0
    max_capacity             = 1
    seconds_until_auto_pause = 300
  }

  storage_encrypted      = true
  database_name          = local.db_name
  master_username        = local.db_user
  master_password        = random_id.db_password.hex
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.database.id]

  backup_retention_period = 1
  # Destroying the cluster keeps a final snapshot (with the PROJECT_NAME tag) of the data.
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-db-final-${random_id.final_snapshot.hex}"
}

# A single serverless writer; the cluster's final snapshot covers the data on destroy.
resource "aws_rds_cluster_instance" "writer" {
  identifier                   = "${var.project_name}-db-1"
  cluster_identifier           = aws_rds_cluster.this.id
  engine                       = aws_rds_cluster.this.engine
  engine_version               = aws_rds_cluster.this.engine_version
  instance_class               = "db.serverless"
  publicly_accessible          = false
  performance_insights_enabled = false
  auto_minor_version_upgrade   = true
}

# ---------------------------------------------------------------- Registry
resource "aws_ecr_repository" "backend" {
  name                 = "${var.project_name}-backend"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Lets Lambda functions in this account pull the image.
resource "aws_ecr_repository_policy" "backend" {
  repository = aws_ecr_repository.backend.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "LambdaPull"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
      Condition = {
        StringLike = {
          "aws:sourceArn" = "arn:${data.aws_partition.current.partition}:lambda:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:function:*"
        }
      }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 3 most recent images (free tier: 500 MB)"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 3
      }
      action = { type = "expire" }
    }]
  })
}

# Builds and pushes the image when its tag is new. Runs on this machine (the HCP workspace uses
# local execution), so it needs Docker and the AWS CLI.
resource "terraform_data" "image" {
  triggers_replace = local.image_tag
  input            = "${aws_ecr_repository.backend.repository_url}:${local.image_tag}"

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      if aws ecr describe-images --repository-name '${aws_ecr_repository.backend.name}' \
        --image-ids 'imageTag=${local.image_tag}' >/dev/null 2>&1; then
        exit 0
      fi
      # Lambda accepts only single-platform images without attestation manifests.
      docker build --platform linux/arm64 --provenance=false --sbom=false --tag '${self.input}' '${local.backend_dir}'
      aws ecr get-login-password | docker login --username AWS --password-stdin '${split("/", aws_ecr_repository.backend.repository_url)[0]}'
      docker push '${self.input}'
    EOT
  }
}

# ------------------------------------------------------------------ Backend
# The function has no internet access, so it gets the token signing keys up front.
data "http" "jwks" {
  url = "${var.cognito_issuer}/.well-known/jwks.json"
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/${var.project_name}/backend"
  retention_in_days = 7
}

resource "aws_iam_role" "function" {
  name_prefix = "${var.project_name}-backend-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Network interfaces in the VPC + CloudWatch Logs.
resource "aws_iam_role_policy_attachment" "function_vpc" {
  role       = aws_iam_role.function.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_function" "backend" {
  function_name = "${var.project_name}-backend"
  package_type  = "Image"
  image_uri     = terraform_data.image.output
  architectures = ["arm64"]
  memory_size   = var.memory_size
  # Covers a cold start: resuming a paused database + migrations check + app startup.
  timeout = 60
  role    = aws_iam_role.function.arn

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.function.id]
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.backend.name
  }

  environment {
    variables = {
      DATABASE_URL         = "postgresql+asyncpg://${local.db_user}:${random_id.db_password.hex}@${aws_rds_cluster.this.endpoint}:${aws_rds_cluster.this.port}/${local.db_name}"
      CORS_ORIGINS         = join(",", var.cors_origins)
      COGNITO_USER_POOL_ID = var.cognito_pool_id
      COGNITO_CLIENT_ID    = var.cognito_client_id
      COGNITO_JWKS         = jsonencode(jsondecode(data.http.jwks.response_body))
      # One request per instance at a time; keeps database connections low as Lambda scales out.
      DB_POOL_SIZE    = "1"
      DB_MAX_OVERFLOW = "1"
      # Lambda Web Adapter: forward requests to uvicorn once /api/health answers.
      AWS_LWA_PORT                 = "8000"
      AWS_LWA_READINESS_CHECK_PATH = "/api/health"
      AWS_LWA_ASYNC_INIT           = "true"
    }
  }

  # The cluster endpoint only accepts connections once its instance exists.
  depends_on = [
    aws_rds_cluster_instance.writer,
    aws_iam_role_policy_attachment.function_vpc,
    aws_ecr_repository_policy.backend,
  ]
}

resource "aws_lambda_function_url" "backend" {
  function_name      = aws_lambda_function.backend.function_name
  authorization_type = "NONE"
}

# Public: the browser calls it directly; the backend's CORS middleware limits which sites may.
# A public function URL needs both permissions. (Function URLs and permissions have no tags.)
resource "aws_lambda_permission" "function_url" {
  function_name          = aws_lambda_function.backend.function_name
  action                 = "lambda:InvokeFunctionUrl"
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "invoke" {
  function_name            = aws_lambda_function.backend.function_name
  action                   = "lambda:InvokeFunction"
  principal                = "*"
  invoked_via_function_url = true
}

output "api_base_url" {
  value = trimsuffix(aws_lambda_function_url.backend.function_url, "/")
}
