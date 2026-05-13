variable "aws_region" {
  description = "AWS region for resources in this environment"
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "Environment name (prod, stg, dev)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name used as resource naming prefix"
  type        = string
  default     = "learn-tf"
}
