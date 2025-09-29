variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "UrlShortner"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_profile" {
  description = "AWS profile to use"
  type        = string
}

variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
}

variable "prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "base_url" {
  description = "Base URL for the URL shortener service"
  type        = string
  default     = ""
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for Route53 zone"
  type        = string
  default     = ""
} 