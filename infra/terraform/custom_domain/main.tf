# Data source for existing Route53 hosted zone
data "aws_route53_zone" "domain_zone" {
  name = var.domain_name
}

# API Gateway Custom Domain Name
resource "aws_api_gateway_domain_name" "custom_domain" {
  domain_name     = var.subdomain_name
  certificate_arn = var.certificate_arn

  tags = {
    Name        = "${var.prefix}-custom-domain"
    Environment = var.environment
    Project     = var.project_name
  }
}

# API Gateway Base Path Mapping
resource "aws_api_gateway_base_path_mapping" "custom_domain_mapping" {
  api_id      = var.api_gateway_id
  stage_name  = var.api_gateway_stage_name
  domain_name = aws_api_gateway_domain_name.custom_domain.domain_name
  
  lifecycle {
    create_before_destroy = true
  }
}

# Route53 record pointing directly to API Gateway custom domain
resource "aws_route53_record" "url_shortener_domain" {
  zone_id = data.aws_route53_zone.domain_zone.zone_id
  name    = var.subdomain_name
  type    = "A"

  alias {
    name                   = aws_api_gateway_domain_name.custom_domain.cloudfront_domain_name
    zone_id                = aws_api_gateway_domain_name.custom_domain.cloudfront_zone_id
    evaluate_target_health = false
  }
} 