variable "aws_region" {
  description = "AWS region for tfstate bucket and OIDC resources"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Project name used as resource naming prefix"
  type        = string
  default     = "learn-tf"
}

variable "aws_account_id" {
  description = "AWS account ID where the tfstate bucket is created"
  type        = string
  default     = "456788081138"
}

variable "github_org" {
  description = "GitHub organization (or user) that owns the repository"
  type        = string
  default     = "Mo3g4u"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "terraform-state-s3-github-actions"
}

variable "environments" {
  description = "Environments managed by Terraform (used for state key prefixes)"
  type        = list(string)
  default     = ["prod", "stg", "dev"]
}

variable "managed_bucket_prefix" {
  description = "Prefix for S3 buckets that GitHub Actions is allowed to manage (sample resource bucket prefix)"
  type        = string
  default     = "learn-tf-sample"
}
