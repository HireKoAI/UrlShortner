output "custom_domain_url" {
  value       = "https://${var.subdomain_name}"
  description = "Custom domain URL for the URL shortener"
}

output "api_gateway_custom_domain" {
  value       = aws_api_gateway_domain_name.custom_domain.domain_name
  description = "API Gateway custom domain name"
}

output "route53_record_name" {
  value       = aws_route53_record.url_shortener_domain.name
  description = "Route53 record name"
}

output "route53_record_fqdn" {
  value       = aws_route53_record.url_shortener_domain.fqdn
  description = "Route53 record FQDN"
} 