variable "rest_api_name" {
  default = null
  description = "Name of the Rest API"
}



variable "request_templates" {
  default = null
}

variable "endpoint_type" {
  default = "EDGE"
}

variable "integration_type" {
  default = "AWS_PROXY"
  description = "AWS Method Integration type e.g.:`MOCK`, `AWS_PROXY`, etc "
}


variable "cache_key_parameters" {
  default = []
  description = "cache key parameters"
}

variable "cache_namespace" {
  default = null
  description = "Name of the cache"
}

variable "timeout" {
  default = null
  description = "Timeout seconds from api gateway"
}

variable "request_parameters" {
  default = {}
  description = "request parameters eg. pathParameters, queryStringParameters, headers"
}

variable "stage_name" {
  default = null
  description = "AWS api gateway stage name"
}

variable "authorization_type" {
  default = "None"
}

variable "authorizer_id" {
  default = null
}


variable "config" {
  type = list(object({
    http_method   = list(string)
    path          = string
    function_name = string
  }))

  description = "List of API Gateway configurations"

  validation {
    condition = alltrue([
      for i in var.config : startswith(i.path, "/")
    ])
    error_message = "Each path must start with a '/'"
  }
}

variable "custom_domain_name" {
  default = ""
}