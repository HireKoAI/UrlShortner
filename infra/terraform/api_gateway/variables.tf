variable "rest_api_name" {
  description = "Name of the API Gateway"
  type        = string
}

variable "config" {
  description = "API Gateway configuration"
  type        = list(object({
    http_method   = list(string)
    path          = string
    function_name = string
    description   = string
  }))
}

variable "stage_name" {
  description = "API Gateway stage name"
  type        = string
} 