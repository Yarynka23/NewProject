<<<<<<< HEAD
output "region" {
  value = data.aws_region.current.region
}

output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.web.id
}

output "cognito_domain" {
  value = "${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.region}.amazoncognito.com"
}

output "issuer" {
  value = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "google_enabled" {
  value = local.has_google
}

output "bucket_name" {
  value = aws_s3_bucket.reports.id
}

output "queue_url" {
  value = aws_sqs_queue.requests.url
}

output "parser_url" {
  value = aws_lambda_function_url.parser.function_url
=======
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
>>>>>>> upstream/main
}
