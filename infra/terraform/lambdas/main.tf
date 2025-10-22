locals {
  triggers = tomap({
    "sns"= "sns.amazonaws.com",
    "api-gateway" = "apigateway.amazonaws.com"
  })

  admin_policies = [
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/AmazonRDSFullAccess",
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess",
    "arn:aws:iam::aws:policy/CloudFrontFullAccess",
    "arn:aws:iam::aws:policy/AmazonSQSFullAccess",
    "arn:aws:iam::aws:policy/AmazonSNSFullAccess",
    "arn:aws:iam::aws:policy/CloudWatchFullAccess",
    "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess",
    "arn:aws:iam::aws:policy/AmazonECS_FullAccess",
  ]
}

# Data source to get the IAM role for Lambda
data "aws_iam_role" "lambda_role" {
  count = var.role_arn == "" ? 1 : 0
  name  = "${split("-", var.lambda_name)[0]}-${split("-", var.lambda_name)[1]}-lambda-dynamodb-role"
}


# Lambda function
resource "aws_lambda_function" "lambda_function" {
  filename         = var.file_path
  function_name    = var.lambda_name
  role            = var.role_arn != "" ? var.role_arn : data.aws_iam_role.lambda_role[0].arn
  handler         = var.handler
  runtime         = var.runtime
  timeout         = var.timeout
  memory_size     = var.memory_size

  source_code_hash = filebase64sha256(var.file_path)

  environment {
    variables = var.environment_variables
  }

  tags = {
    Name = var.lambda_name
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_log_group,
  ]
}

# the list of permissions that are attached to the lambda role and gives lambda full access to the services it needs
resource "aws_iam_role_policy_attachment" "admin_policy" {
  for_each   = toset(local.admin_policies)
  role       = aws_iam_role.lambda_role.id
  policy_arn = each.value
  
}

resource "aws_iam_role_policy" "lambda_full_access" {
  name   = "LambdaFullAccessPolicy"
  role   = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "*"
      Resource = "*"
    }]
  })
}


# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${var.lambda_name}"
  retention_in_days = 14

  tags = {
    Name = "${var.lambda_name}-log-group"
  }
} 