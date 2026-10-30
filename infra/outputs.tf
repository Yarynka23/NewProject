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
}
