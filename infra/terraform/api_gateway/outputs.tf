output "rest_api_invoke_url" {
  description = "Invoke URL of the API Gateway"
  value       = aws_api_gateway_stage.stage.invoke_url
}

output "rest_api_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.rest_api.id
}

output "rest_api_execution_arn" {
  description = "Execution ARN of the API Gateway"
  value       = aws_api_gateway_rest_api.rest_api.execution_arn
}

output "usage_plan_id" {
  description = "ID of the API Gateway Usage Plan"
  value       = aws_api_gateway_usage_plan.main.id
}

output "usage_plan_name" {
  description = "Name of the API Gateway Usage Plan"
  value       = aws_api_gateway_usage_plan.main.name
} 