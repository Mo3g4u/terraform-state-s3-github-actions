locals {
  sample_bucket_name = "learn-tf-sample-${var.environment}"
}

resource "aws_s3_bucket" "sample" {
  bucket = local.sample_bucket_name

  tags = {
    Name    = local.sample_bucket_name
    Purpose = "smoke-test for tfstate backend and CI/CD"
  }
}

resource "aws_s3_bucket_public_access_block" "sample" {
  bucket = aws_s3_bucket.sample.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
