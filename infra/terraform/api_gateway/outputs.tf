output "rest_api_id" {
  value = aws_api_gateway_rest_api.rest_api.id
}

output "rest_api_root_id" {
  value = aws_api_gateway_rest_api.rest_api.root_resource_id
}

output "stage_name" {
  value = var.stage_name
}

output "rest_api_invoke_url" {
  value = var.stage_name == null ? "" : tolist(aws_api_gateway_deployment.deployment.*.invoke_url)[0]
}

output "api_endpoint" {
  value       = aws_api_gateway_rest_api.rest_api.execution_arn
  description = "The endpoint of the API Gateway"
}


output "usage_plan_id" {
  description = "ID of the API Gateway Usage Plan"
  value       = aws_api_gateway_usage_plan.main.id
}

output "usage_plan_name" {
  description = "Name of the API Gateway Usage Plan"
  value       = aws_api_gateway_usage_plan.main.name
} 