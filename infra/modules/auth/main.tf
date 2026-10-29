# Cognito user pool: sign-in with email and password (self sign-up, email verification code),
# a public app client for the SPA, a Cognito domain for OAuth, and Google as an identity
# provider that is created only when google_client_id is set.

variable "project_name" {
  type = string
}

variable "app_urls" {
  type        = list(string)
  description = "Origins of the frontend (no trailing slash). OAuth (Google) redirects back to <origin>/login."
}

variable "google_client_id" {
  type    = string
  default = ""
}

variable "google_client_secret" {
  type      = string
  default   = ""
  sensitive = true
}

locals {
  google_enabled = var.google_client_id != ""
  login_urls     = [for url in var.app_urls : "${url}/login"]
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Deleting the pool deletes every account in it: Terraform refuses to, and make destroy
# removes it from the state first so it is kept (see infra/destroy.sh).
resource "aws_cognito_user_pool" "this" {
  name = "${var.project_name}-users"

  # Users sign in with their email; Cognito emails a code to verify it.
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # A new email (profile page) takes effect only after its code is entered; until then the
  # user keeps signing in with, and recovering the password through, the old one.
  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  username_configuration {
    case_sensitive = false
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  # Mirrored by the signup form (frontend/src/pages/signup-page.tsx).
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_uppercase = false
    require_symbols   = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Cognito's own sender: no SES setup, limited to about 50 emails a day.
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Your Meetings verification code"
    email_message        = "Your Meetings verification code is {####}"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Hosted domain for the OAuth endpoints (needed for Google). Prefixes are global.
resource "aws_cognito_user_pool_domain" "this" {
  user_pool_id = aws_cognito_user_pool.this.id
  domain       = "${var.project_name}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_cognito_identity_provider" "google" {
  count = local.google_enabled ? 1 : 0

  user_pool_id  = aws_cognito_user_pool.this.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id        = var.google_client_id
    client_secret    = var.google_client_secret
    authorize_scopes = "openid email profile"
  }

  attribute_mapping = {
    email          = "email"
    email_verified = "email_verified"
    name           = "name"
  }
}

# Public client (no secret): the SPA talks to Cognito directly with SRP.
resource "aws_cognito_user_pool_client" "web" {
  user_pool_id    = aws_cognito_user_pool.this.id
  name            = "${var.project_name}-web"
  generate_secret = false

  explicit_auth_flows           = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  # Referencing the provider makes the client wait for it.
  supported_identity_providers         = concat(["COGNITO"], aws_cognito_identity_provider.google[*].provider_name)
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = local.login_urls
  logout_urls                          = local.login_urls
}

output "user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.web.id
}

output "domain" {
  value = "${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.current.region}.amazoncognito.com"
}

output "issuer" {
  description = "Issuer of the tokens; the backend checks it"
  value       = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
}

output "google_enabled" {
  value = local.google_enabled
}
