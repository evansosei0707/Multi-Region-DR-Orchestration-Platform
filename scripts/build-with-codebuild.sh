#!/bin/bash
# Quick deployment script using AWS CodeBuild
# This builds Docker images in the cloud (no local Docker needed!)

set -e

echo "========================================="
echo "Building Docker Images via CodeBuild"
echo "========================================="

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="us-east-1"
PROJECT_NAME="dr-platform-build"

# Check if CodeBuild project exists
if ! aws codebuild batch-get-projects --names $PROJECT_NAME --region $AWS_REGION &>/dev/null; then
    echo "Creating CodeBuild project..."
    
    # Create IAM role for CodeBuild
    cat > /tmp/codebuild-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "codebuild.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

    aws iam create-role \
        --role-name ${PROJECT_NAME}-role \
        --assume-role-policy-document file:///tmp/codebuild-trust-policy.json \
        2>/dev/null || true
    
    aws iam attach-role-policy \
        --role-name ${PROJECT_NAME}-role \
        --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser \
        2>/dev/null || true
    
    aws iam attach-role-policy \
        --role-name ${PROJECT_NAME}-role \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess \
        2>/dev/null || true
    
    sleep 5  # Wait for IAM role to propagate
    
    # Create CodeBuild project
    aws codebuild create-project \
        --name $PROJECT_NAME \
        --source type=NO_SOURCE,buildspec=buildspec.yml \
        --artifacts type=NO_ARTIFACTS \
        --environment type=LINUX_CONTAINER,image=aws/codebuild/standard:7.0,computeType=BUILD_GENERAL1_SMALL,privilegedMode=true \
        --service-role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-role \
        --region $AWS_REGION
fi

echo ""
echo "Starting CodeBuild..."
echo "This will build both frontend and backend Docker images and push to ECR"
echo ""

# Start build
BUILD_ID=$(aws codebuild start-build \
    --project-name $PROJECT_NAME \
    --region $AWS_REGION \
    --query 'build.id' \
    --output text)

echo "Build started: $BUILD_ID"
echo "Waiting for build to complete..."

# Wait for build
aws codebuild wait build-complete \
    --ids $BUILD_ID \
    --region $AWS_REGION

# Get build status
BUILD_STATUS=$(aws codebuild batch-get-builds \
    --ids $BUILD_ID \
    --region $AWS_REGION \
    --query 'builds[0].buildStatus' \
    --output text)

if [ "$BUILD_STATUS" = "SUCCEEDED" ]; then
    echo ""
    echo "========================================="
    echo "✅ Build Successful!"
    echo "========================================="
    echo ""
    echo "Images pushed to ECR:"
    echo "  - ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/dr-platform-backend:latest"
    echo "  - ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/dr-platform-frontend:latest"
    echo ""
    echo "Next: Force ECS service update to deploy new images"
    echo ""
else
    echo "❌ Build failed with status: $BUILD_STATUS"
    echo "Check logs: https://console.aws.amazon.com/codesuite/codebuild/projects/$PROJECT_NAME/history"
    exit 1
fi
