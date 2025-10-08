terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  backend "s3" {

  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# Define common environment variables that will be used by all Lambda functions
locals {
  common_environment_variables = {
    PROJECT_NAME        = var.project_name
    ENVIRONMENT         = var.environment
    DYNAMODB_TABLE_NAME = aws_dynamodb_table.URLMappings.name
    DYNAMODB_TABLE_ARN  = aws_dynamodb_table.URLMappings.arn
    BASE_URL            = var.base_url
  }
}

# Lambda function for creating/getting short URLs
module "lambda_getOrCreateShortURL" {
  source                = "./lambdas"
  lambda_name           = "${substr(var.prefix, 0, 32)}_getOrCreateShortURL"
  handler               = "url_shortener_handlers.getOrCreateShortURL.lambda_handler"
  runtime               = "python3.10"
  file_path             = "${path.module}/../../lambda_package.zip"
  environment_variables = local.common_environment_variables
  aws_profile           = var.aws_profile
  aws_region            = var.aws_region
  role_arn              = aws_iam_role.lambda_dynamodb_role.arn
  depends_on            = [aws_dynamodb_table.URLMappings]
}

# Lambda function for URL redirection
module "lambda_redirectURL" {
  source                = "./lambdas"
  lambda_name           = "${substr(var.prefix, 0, 32)}_redirectURL"
  handler               = "url_shortener_handlers.redirectURL.lambda_handler"
  runtime               = "python3.10"
  file_path             = "${path.module}/../../lambda_package.zip"
  environment_variables = local.common_environment_variables
  aws_profile           = var.aws_profile
  aws_region            = var.aws_region
  role_arn              = aws_iam_role.lambda_dynamodb_role.arn
  depends_on            = [aws_dynamodb_table.URLMappings]
}

# API Gateway configuration
module "apigateway" {
  source        = "./api_gateway"
  rest_api_name = var.prefix
  config        = local.api_config
  stage_name    = var.environment
  custom_domain_name = var.domain_name
  depends_on = [
    module.lambda_getOrCreateShortURL,
    module.lambda_redirectURL
  ]
}

# API Gateway Outputs
output "api_gateway_base_url" {
  value       = module.apigateway.rest_api_invoke_url
  description = "Base URL of the API Gateway"
}

output "api_gateway_id" {
  value       = module.apigateway.rest_api_id
  description = "ID of the API Gateway REST API"
}

# Complete API Endpoint URLs (auto-detected from config)
locals {
  api_config = [
    {
      "http_method"   = ["POST"],
      "path"          = "/${var.project_name}/stage/{stage}/tenant/{tenant}/shorten",
      "function_name" = module.lambda_getOrCreateShortURL.lambda_name
      "description"   = "Create Short URL API"
    },
    {
      "http_method"   = ["GET"],
      "path"          = "/{shortId}",
      "function_name" = module.lambda_redirectURL.lambda_name
      "description"   = "Redirect URL API"
    }
  ]
}

output "api_endpoints" {
  value = {
    for config in local.api_config :
    replace(replace(config.description, "/", "_"), " ", "_") => {
      methods     = join(", ", config.http_method)
      path        = config.path
      full_url    = "${module.apigateway.rest_api_invoke_url}${config.path}"
      lambda_name = config.function_name
      description = config.description
    }
  }
  description = "All API endpoints with complete URLs and details"
}

# Lambda Function Names
output "lambda_function_names" {
  value = {
    get_or_create_short_url = module.lambda_getOrCreateShortURL.lambda_name
    redirect_url            = module.lambda_redirectURL.lambda_name
  }
  description = "Names of all Lambda functions"
}

# Custom Domain Module
module "custom_domain" {
  source = "./custom_domain"

  # Only create if all required variables are provided
  count = var.domain_name != "" && var.certificate_arn != "" && var.base_url != "" ? 1 : 0

  domain_name            = var.domain_name
  subdomain_name         = replace(replace(var.base_url, "https://", ""), "http://", "")
  certificate_arn        = var.certificate_arn
  api_gateway_id         = module.apigateway.rest_api_id
  api_gateway_stage_name = var.environment
  prefix                 = var.prefix
  environment            = var.environment
  project_name           = var.project_name

  depends_on = [module.apigateway]
}

# Custom Domain Information
output "base_url_configured" {
  value       = var.base_url != "" ? var.base_url : "Not configured - using API Gateway URL"
  description = "The configured base URL for short links"
}

output "domain_setup_status" {
  value       = var.domain_name != "" && var.certificate_arn != "" && var.base_url != "" ? "Custom domain configured" : "Using default API Gateway domain"
  description = "Status of custom domain configuration"
}

output "custom_domain_url" {
  value       = length(module.custom_domain) > 0 ? module.custom_domain[0].custom_domain_url : "Custom domain not configured"
  description = "Custom domain URL for the URL shortener"
}

output "route53_record_created" {
  value       = length(module.custom_domain) > 0 ? module.custom_domain[0].route53_record_fqdn : "No Route53 record created"
  description = "Route53 record FQDN that was created"
}

# Rate limiting information
output "rate_limiting_info" {
  value = {
    usage_plan_name = module.apigateway.usage_plan_name
    usage_plan_id   = module.apigateway.usage_plan_id
    rate_limit      = "100 requests/second"
    burst_limit     = "200 requests"
    daily_quota     = "10,000 requests/day"
  }
  description = "API Gateway rate limiting configuration"
} 