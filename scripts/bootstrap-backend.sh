#!/bin/bash
# Bootstrap Script: Create Terraform State Backend Resources
# Run this ONCE before initializing Terraform

set -e

echo "============================================"
echo "DR Platform - Bootstrap Terraform Backend"
echo "============================================"

# Configuration
STATE_BUCKET="dr-platform-terraform-state"
LOCK_TABLE="dr-platform-terraform-locks"
REGION="us-east-2"  # Control plane region

echo ""
echo "Creating S3 bucket for Terraform state..."
aws s3api create-bucket \
  --bucket "$STATE_BUCKET" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION" \
  2>/dev/null || echo "Bucket already exists or error occurred"

echo "Enabling versioning on S3 bucket..."
aws s3api put-bucket-versioning \
  --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled

echo "Enabling encryption on S3 bucket..."
aws s3api put-bucket-encryption \
  --bucket "$STATE_BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

echo "Blocking public access on S3 bucket..."
aws s3api put-public-access-block \
  --bucket "$STATE_BUCKET" \
  --public-access-block-configuration '{
    "BlockPublicAcls": true,
    "IgnorePublicAcls": true,
    "BlockPublicPolicy": true,
    "RestrictPublicBuckets": true
  }'

echo ""
echo "Creating DynamoDB table for state locking..."
aws dynamodb create-table \
  --table-name "$LOCK_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION" \
  2>/dev/null || echo "Table already exists or error occurred"

echo ""
echo "============================================"
echo "Bootstrap Complete!"
echo "============================================"
echo ""
echo "S3 Bucket: $STATE_BUCKET"
echo "DynamoDB Table: $LOCK_TABLE"
echo "Region: $REGION"
echo ""
echo "You can now run:"
echo "  cd terraform"
echo "  terraform init"
echo ""
