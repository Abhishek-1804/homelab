# The S3 bucket that holds the Terraform state of tf/infra and tf/test.
# Its own state stays on the laptop (gitignored). If that file is lost the
# bucket is untouched, and `terraform import` brings it back under control.

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = "us-west-1"
}

resource "aws_s3_bucket" "state" {
  bucket = "abhishek1804-homelab-tfstate"

  # deleting it would lose track of everything tf/ manages
  lifecycle {
    prevent_destroy = true
  }
}

# every change keeps the previous state, to recover from a bad apply
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
