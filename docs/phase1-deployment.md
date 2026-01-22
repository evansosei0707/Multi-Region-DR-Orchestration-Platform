# Phase 1 Deployment Guide

## Prerequisites

- AWS CLI configured with credentials
- Terraform >= 1.5.0 installed
- Git installed

## Step 1: Bootstrap Terraform Backend

Before running Terraform, create the S3 bucket and DynamoDB table for state management:

```bash
# Make script executable (Linux/Mac)
chmod +x scripts/bootstrap-backend.sh

# Run bootstrap script
./scripts/bootstrap-backend.sh

# Or manually on Windows with Git Bash:
bash scripts/bootstrap-backend.sh
```

This creates:
- S3 bucket: `dr-platform-terraform-state` in us-east-2
- DynamoDB table: `dr-platform-terraform-locks` in us-east-2

## Step 2: Configure Variables

```bash
cd terraform

# Copy example tfvars
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
# Especially update domain_name if different
```

## Step 3: Initialize Terraform

```bash
terraform init
```

Expected output:
- Backend initialized successfully
- Providers downloaded (AWS, Random)

## Step 4: Validate Configuration

```bash
terraform validate
```

## Step 5: Plan Infrastructure

```bash
terraform plan -out=tfplan
```

Review the plan. You should see resources being created for:
- 3 VPCs (control-plane, primary, DR)
- Networking (subnets, security groups, VPC endpoints)
- RDS instances (primary + replica)
- S3 buckets with replication
- ECR repositories
- ECS clusters and services
- ALB load balancers
- DynamoDB and SSM for DR state

## Step 6: Apply Infrastructure

> **Warning:** This will create billable AWS resources (~$400/month)

```bash
terraform apply tfplan
```

This will take approximately 15-20 minutes.

## Step 7: Verify Deployment

```bash
# Check outputs
terraform output

# Verify VPCs
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=DR-Orchestration-Platform"

# Verify RDS replication
aws rds describe-db-instances --region us-east-1
aws rds describe-db-instances --region us-west-2

# Check S3 replication
aws s3 ls | grep dr-platform
```

## Next Steps

Phase 1 is complete! The infrastructure foundation is deployed.

**What's working:**
- ✅ Multi-region VPCs with VPC endpoints
- ✅ RDS primary with cross-region replica
- ✅ S3 with cross-region replication
- ✅ ECS clusters (no application yet)
- ✅ ECR repositories (empty)
- ✅ ALBs configured

**What's NOT working yet:**
- ❌ No application containers (Phase 3)
- ❌ No failover automation (Phase 4)
- ❌ No DR testing (Phase 5)
- ❌ No dashboard (Phase 6)

**Next:** Proceed to Phase 2 to build the e-commerce application.

## Cleanup (Optional)

To destroy all resources and stop billing:

```bash
terraform destroy
```

> **Note:** RDS instances have deletion protection. You may need to disable it first or set `deletion_protection = false` in the database module.
