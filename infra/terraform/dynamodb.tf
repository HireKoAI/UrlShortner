# DynamoDB table for storing URL mappings
resource "aws_dynamodb_table" "URLMappings" {
  name         = "${var.prefix}-url-mappings"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "shortId"

  attribute {
    name = "shortId"
    type = "S"
  }

  attribute {
    name = "longUrl"
    type = "S"
  }

  # Global Secondary Index for querying by longUrl
  global_secondary_index {
    name            = "longUrl-index"
    hash_key        = "longUrl"
    projection_type = "ALL"
  }

  # TTL configuration for automatic cleanup of expired URLs
  ttl {
    attribute_name = "ttlTimestamp"
    enabled        = true
  }

  tags = {
    Name        = "${var.prefix}-url-mappings"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM role for Lambda functions to access DynamoDB
resource "aws_iam_role" "lambda_dynamodb_role" {
  name = "${var.prefix}-lambda-dynamodb-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.prefix}-lambda-dynamodb-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM policy for DynamoDB access
resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "${var.prefix}-lambda-dynamodb-policy"
  description = "IAM policy for Lambda to access DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.URLMappings.arn,
          "${aws_dynamodb_table.URLMappings.arn}/index/*"
        ]
      }
    ]
  })

  tags = {
    Name        = "${var.prefix}-lambda-dynamodb-policy"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Attach DynamoDB policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy_attachment" {
  role       = aws_iam_role.lambda_dynamodb_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_dynamodb_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
} 