output "lambda_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.lambda_function.arn
}

output "lambda_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.lambda_function.function_name
}

output "lambda_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.lambda_function.invoke_arn
} 
output "lambda_role" {
  value = aws_lambda_function.lambda.role
}

output "iam_role_id" {
  value = aws_iam_role.lambda_role.id
}