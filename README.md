# Multi-Region DR Orchestration Platform

A production-grade disaster recovery orchestration system with automated failover, testing, and cost optimization.

## Architecture

- **Control Plane** (us-east-2): Dashboard, Step Functions, EventBridge
- **Primary Region** (us-east-1): Production ECS services, RDS, S3
- **DR Region** (us-west-2): Warm standby with replicated data

## Endpoints

- `https://app.my-projects-aws.site` - E-commerce application
- `https://dashboard.my-projects-aws.site` - DR Dashboard

## Quick Start

```bash
# 1. Initialize Terraform
cd terraform
terraform init

# 2. Deploy infrastructure
terraform plan
terraform apply

# 3. Build and push application images
cd ../src/ecommerce
./deploy.sh
```

## Project Structure

```
├── terraform/              # Infrastructure as Code
│   ├── modules/           # Reusable modules
│   └── environments/      # Environment configs
├── src/
│   ├── ecommerce/         # E-commerce app (Frontend + Backend)
│   ├── lambdas/           # Control plane functions
│   └── dashboard/         # DR Dashboard
└── docs/                  # Documentation
```

## Key Features

- ✅ Automated failover with Step Functions
- ✅ Weekly DR testing with metrics
- ✅ Cost analytics and optimization
- ✅ Real-time replication monitoring
- ✅ One-click failover from dashboard

## License

MIT
