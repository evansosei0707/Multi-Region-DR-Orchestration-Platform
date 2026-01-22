# -----------------------------------------------------------------------------
# Storage Module - S3 with Cross-Region Replication
# -----------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.primary, aws.dr]
    }
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  type        = string
}

# -----------------------------------------------------------------------------
# Primary S3 Bucket (us-east-1)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "primary" {
  provider = aws.primary

  bucket = "${var.project_name}-primary-${var.account_id}"

  tags = {
    Name   = "${var.project_name}-primary-bucket"
    Region = "primary"
  }
}

# Versioning (required for replication)
resource "aws_s3_bucket_versioning" "primary" {
  provider = aws.primary

  bucket = aws_s3_bucket.primary.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "primary" {
  provider = aws.primary

  bucket = aws_s3_bucket.primary.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "primary" {
  provider = aws.primary

  bucket = aws_s3_bucket.primary.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# DR S3 Bucket (us-west-2)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "dr" {
  provider = aws.dr

  bucket = "${var.project_name}-dr-${var.account_id}"

  tags = {
    Name   = "${var.project_name}-dr-bucket"
    Region = "dr"
  }
}

# Versioning
resource "aws_s3_bucket_versioning" "dr" {
  provider = aws.dr

  bucket = aws_s3_bucket.dr.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "dr" {
  provider = aws.dr

  bucket = aws_s3_bucket.dr.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "dr" {
  provider = aws.dr

  bucket = aws_s3_bucket.dr.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# IAM Role for Replication
# -----------------------------------------------------------------------------

resource "aws_iam_role" "replication" {
  provider = aws.primary

  name = "${var.project_name}-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "s3.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-s3-replication-role"
  }
}

resource "aws_iam_role_policy" "replication" {
  provider = aws.primary

  name = "${var.project_name}-s3-replication-policy"
  role = aws_iam_role.replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.primary.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = "${aws_s3_bucket.primary.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${aws_s3_bucket.dr.arn}/*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Cross-Region Replication Configuration
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_replication_configuration" "primary_to_dr" {
  provider = aws.primary

  # Must have bucket versioning enabled first
  depends_on = [aws_s3_bucket_versioning.primary, aws_s3_bucket_versioning.dr]

  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.primary.id

  rule {
    id     = "replicate-all-objects"
    status = "Enabled"

    filter {}

    destination {
      bucket        = aws_s3_bucket.dr.arn
      storage_class = "STANDARD"

      # Replication Time Control - 15 minute SLA
      replication_time {
        status = "Enabled"
        time {
          minutes = 15
        }
      }

      # Metrics for monitoring
      metrics {
        status = "Enabled"
        event_threshold {
          minutes = 15
        }
      }
    }

    # Delete marker replication
    delete_marker_replication {
      status = "Enabled"
    }
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "primary_bucket_id" {
  description = "Primary S3 bucket ID"
  value       = aws_s3_bucket.primary.id
}

output "primary_bucket_arn" {
  description = "Primary S3 bucket ARN"
  value       = aws_s3_bucket.primary.arn
}

output "dr_bucket_id" {
  description = "DR S3 bucket ID"
  value       = aws_s3_bucket.dr.id
}

output "dr_bucket_arn" {
  description = "DR S3 bucket ARN"
  value       = aws_s3_bucket.dr.arn
}
