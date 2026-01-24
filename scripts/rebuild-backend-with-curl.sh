#!/bin/bash
# Script to rebuild backend image with curl and push to both regions
# Run this in AWS CloudShell

set -e

ACCOUNT_ID="235249476696"
PRIMARY_REGION="us-east-1"
DR_REGION="us-west-2"
IMAGE_NAME="dr-platform-backend"

echo "=== Rebuilding backend image with curl support ==="

# Get the script directory and navigate to backend
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Navigating to backend directory..."
cd "${PROJECT_ROOT}/src/ecommerce/backend"

# Build the image
echo "Building Docker image..."
docker build -t ${IMAGE_NAME}:latest .

# Tag for primary region
echo "Tagging for primary region..."
docker tag ${IMAGE_NAME}:latest ${ACCOUNT_ID}.dkr.ecr.${PRIMARY_REGION}.amazonaws.com/${IMAGE_NAME}:latest
docker tag ${IMAGE_NAME}:latest ${ACCOUNT_ID}.dkr.ecr.${PRIMARY_REGION}.amazonaws.com/${IMAGE_NAME}:v1.1-curl

# Login to ECR primary region
echo "Logging into ECR ${PRIMARY_REGION}..."
aws ecr get-login-password --region ${PRIMARY_REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${PRIMARY_REGION}.amazonaws.com

# Push to primary region
echo "Pushing to primary region..."
docker push ${ACCOUNT_ID}.dkr.ecr.${PRIMARY_REGION}.amazonaws.com/${IMAGE_NAME}:latest
docker push ${ACCOUNT_ID}.dkr.ecr.${PRIMARY_REGION}.amazonaws.com/${IMAGE_NAME}:v1.1-curl

# Wait for ECR cross-region replication to DR region
echo "Waiting for ECR replication to ${DR_REGION}..."
echo "This may take 1-2 minutes..."
sleep 60

# Verify replication completed
echo "Verifying image in DR region..."
aws ecr describe-images --repository-name ${IMAGE_NAME} --region ${DR_REGION} --image-ids imageTag=latest --query 'imageDetails[0].imagePushedAt' --output text || echo "Replication still in progress, wait a bit longer..."

echo "=== Image rebuild and push complete! ==="
echo "Now force new deployment in both regions:"
echo ""
echo "Primary region:"
echo "aws ecs update-service --cluster dr-platform-primary-cluster --service dr-platform-backend --force-new-deployment --region ${PRIMARY_REGION}"
echo ""
echo "DR region:"
echo "aws ecs update-service --cluster dr-platform-dr-cluster --service dr-platform-backend --force-new-deployment --region ${DR_REGION}"
