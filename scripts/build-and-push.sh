#!/bin/bash
# Build and Push E-commerce Application to ECR
# Usage: ./build-and-push.sh [primary|dr]

set -e

REGION_TYPE=${1:-primary}
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [ "$REGION_TYPE" = "primary" ]; then
    AWS_REGION="us-east-1"
elif [ "$REGION_TYPE" = "dr" ]; then
    AWS_REGION="us-west-2"
else
    echo "Usage: $0 [primary|dr]"
    exit 1
fi

PROJECT_NAME="dr-platform"
BACKEND_REPO="${PROJECT_NAME}-backend"
FRONTEND_REPO="${PROJECT_NAME}-frontend"

echo "========================================="
echo "Building and Pushing to $REGION_TYPE region ($AWS_REGION)"
echo "========================================="

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Build and push backend
echo ""
echo "Building backend..."
cd src/ecommerce/backend
docker build -t ${BACKEND_REPO}:latest .
docker tag ${BACKEND_REPO}:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${BACKEND_REPO}:latest
docker tag ${BACKEND_REPO}:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${BACKEND_REPO}:$(git rev-parse --short HEAD)

echo "Pushing backend to ECR..."
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${BACKEND_REPO}:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${BACKEND_REPO}:$(git rev-parse --short HEAD)

cd ../../..

# Build and push frontend
echo ""
echo "Building frontend..."
cd src/ecommerce/frontend
docker build -t ${FRONTEND_REPO}:latest .
docker tag ${FRONTEND_REPO}:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${FRONTEND_REPO}:latest
docker tag ${FRONTEND_REPO}:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${FRONTEND_REPO}:$(git rev-parse --short HEAD)

echo "Pushing frontend to ECR..."
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${FRONTEND_REPO}:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${FRONTEND_REPO}:$(git rev-parse --short HEAD)

cd ../../..

echo ""
echo "========================================="
echo "Build and Push Complete!"
echo "========================================="
echo ""
echo "Backend Image: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${BACKEND_REPO}:latest"
echo "Frontend Image: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${FRONTEND_REPO}:latest"
echo ""
echo "Next steps:"
echo "1. Initialize database: python src/ecommerce/backend/init_db.py"
echo "2. ECS services will automatically pull the new images"
echo ""
