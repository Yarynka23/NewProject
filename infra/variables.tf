# Set by the infra scripts from .env as TF_VAR_* environment variables.

variable "project_name" {
  type        = string
  default     = "meetings"
  description = "Prefix for every resource name; also the value of the PROJECT_NAME tag."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_name))
    error_message = "project_name must be lowercase letters, digits and dashes, starting with a letter."
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "lambda_memory" {
  type        = number
  default     = 512
  description = "Backend Lambda memory in MB (CPU scales with it)."
}

variable "extra_cors_origins" {
  type        = string
  default     = ""
  description = "Comma-separated origins allowed to call the API besides the CloudFront address and the custom domain."
}

variable "domain_name" {
  type        = string
  default     = ""
  description = "Optional custom domain for the frontend, e.g. app.example.com."
}

variable "hosted_zone_id" {
  type        = string
  default     = ""
  description = "Optional Route 53 hosted zone of domain_name. If set, the DNS records are created here; otherwise add them at your DNS provider."
}

variable "google_client_id" {
  type        = string
  default     = ""
  description = "Google OAuth client id; leave empty to keep Google sign-in disabled."
}

variable "google_client_secret" {
  type      = string
  default   = ""
  sensitive = true
}
