# Meetings app on AWS: the frontend (S3 + CloudFront), Cognito, and the backend (Lambda +
# Aurora Serverless v2). The frontend comes first because both others need its addresses:
# Cognito redirects back to it and the API allows it as a CORS origin.

locals {
  # The CloudFront address and, once attached, the custom domain.
  app_urls = compact([module.frontend.app_url, module.frontend.custom_domain_url])
}

module "frontend" {
  source = "./modules/frontend"
  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  project_name   = var.project_name
  domain_name    = var.domain_name
  hosted_zone_id = var.hosted_zone_id
}

module "auth" {
  source = "./modules/auth"

  project_name         = var.project_name
  app_urls             = concat(["http://localhost:5173", "http://localhost:3000"], local.app_urls)
  google_client_id     = var.google_client_id
  google_client_secret = var.google_client_secret
}

module "backend" {
  source = "./modules/backend"

  project_name      = var.project_name
  memory_size       = var.lambda_memory
  cors_origins      = distinct(concat(local.app_urls, compact(split(",", replace(var.extra_cors_origins, " ", "")))))
  cognito_issuer    = module.auth.issuer
  cognito_pool_id   = module.auth.user_pool_id
  cognito_client_id = module.auth.user_pool_client_id
}

# ------------------------------------------------------------ Frontend upload
locals {
  frontend_dir = "${path.root}/../frontend"
  # The bundle has the API and Cognito settings baked in.
  frontend_build_env = {
    VITE_API_URL           = module.backend.api_base_url
    COGNITO_USER_POOL_ID   = module.auth.user_pool_id
    COGNITO_CLIENT_ID      = module.auth.user_pool_client_id
    COGNITO_DOMAIN         = module.auth.domain
    COGNITO_GOOGLE_ENABLED = tostring(module.auth.google_enabled)
  }
}

# Builds the frontend and uploads it whenever its sources or settings change. Runs on this
# machine (the HCP workspace uses local execution), so it needs Node.js and the AWS CLI.
resource "terraform_data" "frontend_upload" {
  triggers_replace = [
    local.frontend_build_env,
    module.frontend.bucket_name,
    sha1(join("", [
      for f in sort(setunion(
        fileset(local.frontend_dir, "{index.html,package-lock.json,vite.config.ts,tsconfig*.json}"),
        fileset(local.frontend_dir, "{public,src}/**"),
      )) :
      "${f}:${filesha1("${local.frontend_dir}/${f}")}"
    ])),
  ]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    working_dir = local.frontend_dir
    environment = local.frontend_build_env
    command     = <<-EOT
      set -euo pipefail
      npm ci
      npm run build
      # Hashed assets never change, so browsers may cache them forever; everything else is revalidated.
      aws s3 sync dist/assets 's3://${module.frontend.bucket_name}/assets' --delete \
        --cache-control 'public, max-age=31536000, immutable'
      aws s3 sync dist 's3://${module.frontend.bucket_name}' --delete --exclude 'assets/*' \
        --cache-control 'no-cache'
      # "/*" counts as a single path against the 1,000 free invalidation paths per month.
      id="$(aws cloudfront create-invalidation --distribution-id '${module.frontend.distribution_id}' \
        --paths '/*' --query Invalidation.Id --output text)"
      aws cloudfront wait invalidation-completed --distribution-id '${module.frontend.distribution_id}' --id "$id"
    EOT
  }
}
