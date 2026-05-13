output "tfstate_bucket_name" {
  description = "Name of the S3 bucket that stores Terraform state for all environments"
  value       = aws_s3_bucket.tfstate.bucket
}

output "tfstate_bucket_arn" {
  description = "ARN of the tfstate S3 bucket"
  value       = aws_s3_bucket.tfstate.arn
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider (data source: existing shared resource)"
  value       = data.aws_iam_openid_connect_provider.github.arn
}

output "github_actions_role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions via OIDC"
  value       = aws_iam_role.github_actions_terraform.arn
}

output "github_actions_role_name" {
  description = "Name of the IAM role assumed by GitHub Actions via OIDC"
  value       = aws_iam_role.github_actions_terraform.name
}
