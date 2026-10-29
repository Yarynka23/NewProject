# Frontend on a private S3 bucket behind CloudFront (pay-as-you-go pricing, no flat-rate
# plan). The app calls the backend's Lambda function URL directly. With domain_name set, the
# distribution also answers on that domain, with an ACM certificate from us-east-1.

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

variable "project_name" {
  type = string
}

variable "domain_name" {
  type    = string
  default = ""
}

variable "hosted_zone_id" {
  type    = string
  default = ""
}

locals {
  has_domain      = var.domain_name != ""
  has_hosted_zone = local.has_domain && var.hosted_zone_id != ""
}

# Emptied on destroy: the files are build output, uploaded again by make deploy.
resource "aws_s3_bucket" "this" {
  bucket_prefix = "${var.project_name}-frontend-"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Origin access controls, bucket policies and DNS records have no tags.
resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.project_name}-frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Only this distribution may read the bucket.
resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.this.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.this.arn }
      }
    }]
  })
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# --------------------------------------------------------------- Custom domain
resource "aws_acm_certificate" "this" {
  count    = local.has_domain ? 1 : 0
  provider = aws.us_east_1

  domain_name       = var.domain_name
  validation_method = "DNS"

  # Switching domains: the new certificate must exist before CloudFront lets go of the old one.
  lifecycle {
    create_before_destroy = true
  }
}

locals {
  validation_option = local.has_domain ? one(aws_acm_certificate.this[0].domain_validation_options) : null
}

resource "aws_route53_record" "validation" {
  count = local.has_hosted_zone ? 1 : 0

  zone_id         = var.hosted_zone_id
  name            = local.validation_option.resource_record_name
  type            = local.validation_option.resource_record_type
  records         = [local.validation_option.resource_record_value]
  ttl             = 300
  allow_overwrite = true
}

# Waits until ACM has issued the certificate. Without Route 53 that is once the record from
# the certificate_validation_record output exists at your DNS provider (infra/deploy.sh
# prints it before this wait starts).
resource "aws_acm_certificate_validation" "this" {
  count    = local.has_domain ? 1 : 0
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = local.has_hosted_zone ? [aws_route53_record.validation[0].fqdn] : null
}

# ---------------------------------------------------------------- Distribution
resource "aws_cloudfront_distribution" "this" {
  comment             = "${var.project_name} frontend"
  enabled             = true
  default_root_object = "index.html"
  http_version        = "http2and3"
  is_ipv6_enabled     = true
  # North America and Europe: the cheapest; pay-as-you-go includes 1 TB and 10M requests a month.
  price_class = "PriceClass_100"
  aliases     = local.has_domain ? [var.domain_name] : []

  # Client-side routes (/home, /login, /signup) are not files in the bucket: S3 answers 403
  # for them, so serve index.html and let the router take over.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }
  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  origin {
    origin_id                = "frontend"
    domain_name              = aws_s3_bucket.this.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    target_origin_id       = "frontend"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  viewer_certificate {
    cloudfront_default_certificate = !local.has_domain
    acm_certificate_arn            = local.has_domain ? aws_acm_certificate_validation.this[0].certificate_arn : null
    ssl_support_method             = local.has_domain ? "sni-only" : null
    minimum_protocol_version       = local.has_domain ? "TLSv1.2_2021" : "TLSv1"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

# Z2FDTNDATAQYW2 is the fixed hosted zone of every CloudFront distribution.
resource "aws_route53_record" "alias" {
  for_each = local.has_hosted_zone ? toset(["A", "AAAA"]) : toset([])

  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = each.key

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }
}

output "bucket_name" {
  value = aws_s3_bucket.this.id
}

output "distribution_id" {
  value = aws_cloudfront_distribution.this.id
}

output "distribution_domain" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "app_url" {
  value = "https://${aws_cloudfront_distribution.this.domain_name}"
}

output "custom_domain_url" {
  value = local.has_domain ? "https://${var.domain_name}" : null
}

output "certificate_validation_record" {
  value = local.has_domain ? "${local.validation_option.resource_record_type}  ${local.validation_option.resource_record_name}  ->  ${local.validation_option.resource_record_value}" : null
}
