locals {
  async_header = {"integration.request.header.X-Amz-Invocation-Type": "'Event'"}
  resource_config = {
    for i in data.aws_api_gateway_resource.resource: i.path => i.id
  }
  function_config = {
    for i in data.aws_lambda_function.lambda: i.function_name => i.invoke_arn
  }
  method_config = flatten([
    for i in var.config: [
      for j in i.http_method: {
        path = i.path
        method = j
        resource_id = local.resource_config[i.path]
        function_name = i.function_name
      }
    ]
  ])
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_lambda_function" "lambda" {
  count = length(var.config)
  function_name = var.config[count.index].function_name
}

resource "aws_api_gateway_rest_api" "rest_api" {
  name = var.rest_api_name
  body = jsonencode(
    {
      openapi = "3.0.1",
      info = {
        title = var.rest_api_name,
        version = "1.0"
      },
      paths = {
        for i in var.config: i.path => {}
      }
    }
  )
  put_rest_api_mode = "overwrite"
  endpoint_configuration {
    types = [var.endpoint_type]
  }

  lifecycle {
    prevent_destroy = true
  }
}

data "aws_api_gateway_resource" "resource" {
  count = length(var.config)
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  path = var.config[count.index].path
  depends_on = [
    aws_api_gateway_rest_api.rest_api,
  ]
}

resource "aws_api_gateway_method" "method" {
  count = length(local.method_config)
  authorization = var.authorization_type
  authorizer_id = var.authorizer_id
  http_method = local.method_config[count.index].method
  resource_id = local.method_config[count.index].resource_id
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  request_parameters = {for k,v in var.request_parameters: "method.request.${k}" => v}
  depends_on = [
    aws_api_gateway_rest_api.rest_api,
    data.aws_api_gateway_resource.resource
  ]
  lifecycle {
    create_before_destroy = false
  }
}


resource "aws_api_gateway_integration" "integration" {
  count = length(local.method_config)
  http_method = local.method_config[count.index].method
  resource_id = local.method_config[count.index].resource_id
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  type        = var.integration_type
  uri         = local.function_config[local.method_config[count.index].function_name]
  cache_key_parameters = [for i in var.cache_key_parameters: "method.request.path.${i}"]
  cache_namespace      = var.cache_namespace
  timeout_milliseconds = var.timeout
  integration_http_method = "POST"
  depends_on = [aws_api_gateway_method.method]
  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_api_gateway_integration_response" "integration_response" {
  count = length(local.method_config)
  http_method = local.method_config[count.index].method
  resource_id = local.method_config[count.index].resource_id
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  status_code = 200
  response_parameters = {
  "method.response.header.Access-Control-Allow-Headers" = "'*'",
  "method.response.header.Access-Control-Allow-Methods" = "'*'",
  "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
  depends_on = [
    aws_api_gateway_method.method,
    aws_api_gateway_integration.integration,
    aws_api_gateway_method_response.method_response
  ]
  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_api_gateway_method_response" "method_response" {
  count = length(local.method_config)
  http_method = local.method_config[count.index].method
  resource_id = local.method_config[count.index].resource_id
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  status_code = 200
  response_parameters = {
  "method.response.header.Access-Control-Allow-Headers" = true,
  "method.response.header.Access-Control-Allow-Methods" = true,
  "method.response.header.Access-Control-Allow-Origin" = true
  }
  depends_on = [
    aws_api_gateway_method.method
  ]
  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_api_gateway_method" "options_method" {
  for_each = local.resource_config
  http_method = "OPTIONS"
  resource_id = local.resource_config[each.key]
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  authorization = "None"
  depends_on = [aws_api_gateway_method.method]
  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_api_gateway_method_response" "options_response" {
  for_each = aws_api_gateway_method.options_method
  http_method = each.value.http_method
  resource_id = each.value.resource_id
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  status_code = 200
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin" = true
  }
  depends_on = [aws_api_gateway_method.options_method]
  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_api_gateway_integration" "options_integration" {
  for_each = aws_api_gateway_method.options_method
  http_method = each.value.http_method
  resource_id = each.value.resource_id
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  type = "MOCK"
  request_templates = {
    "application/json" = <<EOF
{"statusCode": 200}
EOF
  }
  depends_on = [aws_api_gateway_method.options_method]
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  for_each = aws_api_gateway_method.options_method
  http_method = each.value.http_method
  resource_id = each.value.resource_id
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  status_code = 200
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'*'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'",
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
  depends_on = [
    aws_api_gateway_integration.options_integration,
    aws_api_gateway_method_response.options_response,
    aws_api_gateway_method.options_method
  ]
}


resource "aws_lambda_permission" "lambda_permission" {
  count             = length(local.method_config)
  action            = "lambda:InvokeFunction"
  principal         = "apigateway.amazonaws.com"
  function_name     = local.method_config[count.index].function_name
  source_arn = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.rest_api.id}/*/${local.method_config[count.index].method}${local.method_config[count.index].path}"
  depends_on = [ 
    aws_api_gateway_method.method
  ]
  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_api_gateway_deployment" "deployment" {
  count = var.stage_name == null ? 0 : 1
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  variables = {"timestamp" = timestamp()}
  depends_on = [ 
    aws_api_gateway_deployment.deployment,

    aws_api_gateway_method.method,
    aws_api_gateway_integration.integration,

    aws_api_gateway_method_response.method_response,
    aws_api_gateway_integration_response.integration_response,


    aws_api_gateway_method.options_method,
    aws_api_gateway_integration.options_integration,

    aws_api_gateway_method_response.options_response,
    aws_api_gateway_integration_response.options_integration_response,

    aws_api_gateway_base_path_mapping.custom_domain_mapping
  ]
  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_api_gateway_stage" "stage" {
  count = var.stage_name == null ? 0 : 1
  deployment_id = aws_api_gateway_deployment.deployment[0].id
  rest_api_id   = aws_api_gateway_rest_api.rest_api.id
  stage_name    = var.stage_name

  lifecycle {
    replace_triggered_by = [ aws_api_gateway_deployment.deployment ]
  }
}

resource "aws_api_gateway_gateway_response" "response_4xx" {
  count = var.rest_api_name == null ? 0 : 1
  rest_api_id   = aws_api_gateway_rest_api.rest_api.id
  status_code   = "401"
  response_type = "DEFAULT_4XX"

  response_templates = {
    "application/json" = "{\"message\":$context.error.messageString}"
  }

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin" = "'*'",
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'*'",
    "gatewayresponse.header.Access-Control-Allow-Methods" = "'OPTIONS,POST,GET'"
  }
  depends_on = [aws_api_gateway_rest_api.rest_api]
}

resource "aws_api_gateway_gateway_response" "response_5xx" {
  count = var.rest_api_name == null ? 0 : 1
  rest_api_id   = aws_api_gateway_rest_api.rest_api.id
  status_code   = "503"
  response_type = "DEFAULT_5XX"

  response_templates = {
    "application/json" = "{\"message\":$context.error.messageString}"
  }

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin" = "'*'",
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'*'",
    "gatewayresponse.header.Access-Control-Allow-Methods" = "'OPTIONS,POST,GET'"
  }
  depends_on = [aws_api_gateway_rest_api.rest_api]
}

# Usage Plan for rate limiting
resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.rest_api_name}-${var.stage_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.rest_api.id
    stage  = var.stage_name

    dynamic "throttle" {
      for_each = local.method_config
      content {
        path = "${throttle.value.path}/${throttle.value.method}"
        rate_limit  = 100         # 100 requests per second steady rate
        burst_limit = 200         # 200 requests burst capacity
      }
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
  depends_on = [
    aws_api_gateway_method.method,
    aws_api_gateway_integration.integration,
    aws_api_gateway_stage.stage
  ]
} 