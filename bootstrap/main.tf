terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform-bootstrap"
      Purpose   = "tfstate-and-oidc"
    }
  }
}

locals {
  tfstate_bucket_name = "${var.project_name}-tfstate-${var.aws_account_id}"
  iam_role_name       = "github-actions-terraform"

  # state key path per environment, must match terraform/environments/<env>/backend.tf
  state_keys = [for e in var.environments : "${e}/terraform.tfstate"]
}

# ---------------------------------------------------------------------------
# tfstate S3 bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "tfstate" {
  bucket = local.tfstate_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# ---------------------------------------------------------------------------
# GitHub OIDC provider (shared resource, looked up by URL)
#
# OIDC providers are 1-per-AWS-account. We reference the existing provider
# instead of creating one to avoid ownership conflicts with other projects
# in the same account.
# ---------------------------------------------------------------------------

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# ---------------------------------------------------------------------------
# IAM role for GitHub Actions (OIDC AssumeRole)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions_terraform" {
  name                 = local.iam_role_name
  description          = "Role assumed by GitHub Actions OIDC for Terraform operations"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_assume_role.json
  max_session_duration = 3600
}

# ---------------------------------------------------------------------------
# IAM policy: tfstate S3 access (read/write + native lock)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "tfstate_access" {
  statement {
    sid       = "ListTfstateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tfstate.arn]
  }

  statement {
    sid    = "ReadWriteTfstateObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      for k in local.state_keys : "${aws_s3_bucket.tfstate.arn}/${k}"
    ]
  }

  # Native locking: Terraform v1.10+ writes <key>.tflock alongside the state object
  statement {
    sid    = "ReadWriteTflockObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      for k in local.state_keys : "${aws_s3_bucket.tfstate.arn}/${k}.tflock"
    ]
  }
}

resource "aws_iam_policy" "tfstate_access" {
  name        = "${local.iam_role_name}-tfstate-access"
  description = "Read/write access to the Terraform state bucket and lockfile objects"
  policy      = data.aws_iam_policy_document.tfstate_access.json
}

resource "aws_iam_role_policy_attachment" "tfstate_access" {
  role       = aws_iam_role.github_actions_terraform.name
  policy_arn = aws_iam_policy.tfstate_access.arn
}

# ---------------------------------------------------------------------------
# IAM policy: minimal real-resource management
#
# Scope kept intentionally narrow: only allows managing S3 buckets whose name
# starts with var.managed_bucket_prefix. Expand this policy as the workload
# grows; revisit before adding non-S3 resources to the environment stacks.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "managed_resources" {
  statement {
    sid    = "ListAllBucketsForPlan"
    effect = "Allow"
    actions = [
      "s3:ListAllMyBuckets",
      "s3:GetBucketLocation",
    ]
    resources = ["*"]
  }

  # Full S3 access scoped strictly to buckets matching the managed prefix.
  # Action wildcard is safe here because the resource ARN restricts blast radius
  # to "<prefix>-*" buckets only. Enumerating actions individually is brittle —
  # several S3 IAM actions don't follow the Get/Put/ListBucket* naming pattern
  # (e.g. s3:GetAccelerateConfiguration, s3:PutBucketTagging) and missing one
  # breaks Terraform's post-create refresh.
  statement {
    sid     = "ManagePrefixedBuckets"
    effect  = "Allow"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${var.managed_bucket_prefix}-*",
      "arn:aws:s3:::${var.managed_bucket_prefix}-*/*",
    ]
  }
}

resource "aws_iam_policy" "managed_resources" {
  name        = "${local.iam_role_name}-managed-resources"
  description = "Minimal permissions for resources managed by Terraform environment stacks"
  policy      = data.aws_iam_policy_document.managed_resources.json
}

resource "aws_iam_role_policy_attachment" "managed_resources" {
  role       = aws_iam_role.github_actions_terraform.name
  policy_arn = aws_iam_policy.managed_resources.arn
}
