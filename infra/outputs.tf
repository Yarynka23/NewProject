output "app_url" {
  value = module.frontend.app_url
}

output "custom_domain_url" {
  value = module.frontend.custom_domain_url
}

output "distribution_domain" {
  description = "Target for a CNAME record when the custom domain's DNS is not in Route 53"
  value       = module.frontend.distribution_domain
}

output "certificate_validation_record" {
  description = "DNS record that proves ownership of the custom domain (add it yourself without Route 53)"
  value       = module.frontend.certificate_validation_record
}

output "api_url" {
  value = "${module.backend.api_base_url}/api"
}

output "docs_url" {
  value = "${module.backend.api_base_url}/api/docs"
}

output "cognito_user_pool_id" {
  value = module.auth.user_pool_id
}

output "cognito_client_id" {
  value = module.auth.user_pool_client_id
}

output "cognito_domain" {
  description = "Cognito domain for OAuth redirects (Google)"
  value       = module.auth.domain
}

output "cognito_google_enabled" {
  value = module.auth.google_enabled
}
