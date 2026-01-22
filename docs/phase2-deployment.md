# Phase 2: E-commerce Application Deployment Guide

## Overview

This guide covers building and deploying the e-commerce application to your Multi-Region DR infrastructure.

## Application Architecture

```
┌─────────────────┐      ┌─────────────────┐
│  React Frontend │◄────►│   Flask Backend │
│   (Next.js)     │      │     (API)       │
│   Port: 3000    │      │   Port: 8080    │
└─────────────────┘      └────────┬────────┘
                                  │
                         ┌────────▼────────┐
                         │  PostgreSQL RDS │
                         │   (Products,    │
                         │    Orders)      │
                         └─────────────────┘
```

## Prerequisites

- Docker installed locally
- AWS CLI configured
- Infrastructure from Phase 1 deployed
- Git for version tagging

## Step 1: Initialize Database

The database needs to be initialized with tables and seed data.

### Option A: From Local Machine

```bash
# Set environment variables
export AWS_REGION=us-east-1
export DB_SECRET=arn:aws:secret:manager:us-east-1:ACCOUNT_ID:secret:dr-platform-primary-db-credentials-XXXXXX

# Run initialization script
cd src/ecommerce/backend
python init_db.py
```

### Option B: Run as ECS Task (Recommended)

```bash
# Build backend image first
cd src/ecommerce/backend
docker build -t dr-platform-backend:latest .

# Get ECR URI from terraform output
terraform output backend_ecr_primary

# Tag and push
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
docker tag dr-platform-backend:latest ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/dr-platform-backend:latest

aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com

docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/dr-platform-backend:latest

# Run init task
aws ecs run-task \
  --cluster dr-platform-primary-cluster \
  --task-definition dr-platform-backend \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[SUBNET_ID],securityGroups=[SG_ID]}" \
  --overrides '{"containerOverrides":[{"name":"backend","command":["python","init_db.py"]}]}' \
  --region us-east-1
```

## Step 2: Build Docker Images

### Quick Build (Automated Script)

```bash
# For primary region
./scripts/build-and-push.sh primary

# For DR region (ECR replication will handle this automatically)
```

### Manual Build

**Backend:**
```bash
cd src/ecommerce/backend
docker build -t dr-platform-backend:latest .
```

**Frontend:**
```bash
cd src/ecommerce/frontend
docker build -t dr-platform-frontend:latest .
```

## Step 3: Push to ECR

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Backend
docker tag dr-platform-backend:latest ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/dr-platform-backend:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/dr-platform-backend:latest

# Frontend
docker tag dr-platform-frontend:latest ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/dr-platform-frontend:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/dr-platform-frontend:latest
```

## Step 4: Update ECS Services

ECS services are configured to automatically pull the `:latest` tag. Force a new deployment:

```bash
# Update frontend service
aws ecs update-service \
  --cluster dr-platform-primary-cluster \
  --service dr-platform-frontend \
  --force-new-deployment \
  --region us-east-1

# Update backend service
aws ecs update-service \
  --cluster dr-platform-primary-cluster \
  --service dr-platform-backend \
  --force-new-deployment \
  --region us-east-1
```

## Step 5: Verify Deployment

### Check ECS Service Status

```bash
aws ecs describe-services \
  --cluster dr-platform-primary-cluster \
  --services dr-platform-frontend dr-platform-backend \
  --region us-east-1
```

### Test Backend Health

```bash
# Get ALB DNS from terraform output
terraform output primary_alb_dns

# Test health endpoint
curl http://PRIMARY_ALB_DNS/health
```

Expected response:
```json
{
  "status": "healthy",
  "region": "us-east-1",
  "region_type": "primary",
  "database": "healthy",
  "timestamp": "2026-01-22T17:00:00.000000"
}
```

### Test Products API

```bash
curl http://PRIMARY_ALB_DNS/api/products
```

### Access Frontend

Open browser to: `http://PRIMARY_ALB_DNS`

You should see the product listing with 8 sample products.

## Step 6: Verify DR Region

After ~5-10 minutes, ECR replication should complete:

```bash
# Check DR region
aws ecr describe-images \
  --repository-name dr-platform-backend \
  --region us-west-2
```

ECS tasks in DR region will automatically update when you force deployment:

```bash
aws ecs update-service \
  --cluster dr-platform-dr-cluster \
  --service dr-platform-backend \
  --force-new-deployment \
  --region us-west-2
```

## Troubleshooting

### Backend Can't Connect to Database

Check security group rules:
```bash
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=dr-platform-primary-rds-sg" \
  --region us-east-1
```

### Frontend Can't Reach Backend

Check ALB listener rules:
```bash
aws elbv2 describe-listeners \
  --load-balancer-arn $(terraform output -raw primary_alb_arn)
```

### Database Not Initialized

Run init script again:
```bash
export AWS_REGION=us-east-1
export DB_SECRET=$(terraform output -raw primary_db_secret_arn)
python src/ecommerce/backend/init_db.py
```

## Next Steps

After successful deployment:
1. Configure Route53 to point `app.my-projects-aws.site` to ALB
2. Test failover to DR region
3. Implement CI/CD pipeline (Phase 3)

---

**Phase 2 Complete!** ✅ The e-commerce application is now running in both regions.
