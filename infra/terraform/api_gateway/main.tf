# Get Lambda function details
data "aws_lambda_function" "lambda_functions" {
  count         = length(var.config)
  function_name = var.config[count.index].function_name
}

# Create API Gateway REST API using OpenAPI spec (like working reference)
resource "aws_api_gateway_rest_api" "rest_api" {
  name        = var.rest_api_name
  description = "URL Shortener API"
  
  body = jsonencode({
    openapi = "3.0.1",
    info = {
      title   = var.rest_api_name,
      version = "1.0"
    },
    paths = {
      for i in var.config : i.path => {}
    }
  })
  
  put_rest_api_mode = "overwrite"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Get the created resources using data sources (like working reference)
data "aws_api_gateway_resource" "resource" {
  count       = length(var.config)
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  path        = var.config[count.index].path
  depends_on = [
    aws_api_gateway_rest_api.rest_api,
  ]
}

# Create local configs for method handling
locals {
  resource_config = {
    for i in data.aws_api_gateway_resource.resource : i.path => i.id
  }
  function_config = {
    for i in data.aws_lambda_function.lambda_functions : i.function_name => i.invoke_arn
  }
  method_config = flatten([
    for i in var.config : [
      for j in i.http_method : {
        path          = i.path
        method        = j
        resource_id   = local.resource_config[i.path]
        function_name = i.function_name
      }
    ]
  ])
}

# Create methods for each configuration
resource "aws_api_gateway_method" "methods" {
  count         = length(local.method_config)
  authorization = "NONE"
  http_method   = local.method_config[count.index].method
  resource_id   = local.method_config[count.index].resource_id
  rest_api_id   = aws_api_gateway_rest_api.rest_api.id
  
  depends_on = [
    aws_api_gateway_rest_api.rest_api,
    data.aws_api_gateway_resource.resource
  ]
}

# Create integrations for each method
resource "aws_api_gateway_integration" "integrations" {
  count                   = length(local.method_config)
  http_method             = local.method_config[count.index].method
  resource_id             = local.method_config[count.index].resource_id
  rest_api_id             = aws_api_gateway_rest_api.rest_api.id
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = local.function_config[local.method_config[count.index].function_name]
  
  depends_on = [aws_api_gateway_method.methods]
}

# Lambda permissions
resource "aws_lambda_permission" "api_gateway_invoke" {
  count         = length(local.method_config)
  statement_id  = "AllowExecutionFromAPIGateway-${count.index}"
  action        = "lambda:InvokeFunction"
  function_name = local.method_config[count.index].function_name
  principal     = "apigateway.amazonaws.com"
  
  source_arn = "${aws_api_gateway_rest_api.rest_api.execution_arn}/*/${local.method_config[count.index].method}${local.method_config[count.index].path}"
  
  depends_on = [aws_api_gateway_method.methods]
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.rest_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      for config in var.config : {
        path        = config.path
        http_method = config.http_method
        function    = config.function_name
      }
    ]))
  }

  depends_on = [
    aws_api_gateway_method.methods,
    aws_api_gateway_integration.integrations,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway Stage
resource "aws_api_gateway_stage" "stage" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.rest_api.id
  stage_name    = var.stage_name

  tags = {
    Name = "${var.rest_api_name}-${var.stage_name}"
  }
}

# Usage Plan for rate limiting
resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.rest_api_name}-${var.stage_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.rest_api.id
    stage  = aws_api_gateway_stage.stage.stage_name
    
    # Method-specific throttling
    throttle {
      path        = "/*/*"      # Apply to all paths and methods
      rate_limit  = 100         # 100 requests per second steady rate
      burst_limit = 200         # 200 requests burst capacity
    }
  }

  # Overall quota limits
  quota_settings {
    limit  = 10000    # 10,000 requests per day
    period = "DAY"
  }

  # Default throttling for the entire usage plan
  throttle_settings {
    rate_limit  = 100    # 100 RPS steady rate
    burst_limit = 200    # 200 burst capacity
  }

  tags = {
    Name = "${var.rest_api_name}-usage-plan"
  }
  
  depends_on = [aws_api_gateway_stage.stage]
} 