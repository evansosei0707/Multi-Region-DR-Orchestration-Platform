# Architecture Documentation

## Overview

This document describes the architecture of the Multi-Region DR Orchestration Platform.

## Components

### Control Plane (us-east-2)

The control plane is deployed in a separate region from both primary and DR to ensure it remains available during regional failures.

**Components:**
- **Step Functions**: Orchestrates failover and failback workflows
- **Lambda Functions**: Individual tasks for health checking, database promotion, DNS updates
- **DynamoDB**: Stores DR state, test results, and cost metrics
- **API Gateway**: Dashboard API endpoints
- **EventBridge**: Scheduled DR tests and automated failover triggers

### Primary Region (us-east-1)

Production workloads run here during normal operation.

**Components:**
- **ECS Fargate**: Frontend and Backend services (auto-scaled 2-10 tasks)
- **RDS PostgreSQL**: Primary database with Multi-AZ
- **S3**: Application assets with Cross-Region Replication
- **ALB**: Application Load Balancer serving app.my-projects-aws.site
- **ECR**: Container registry with replication to DR

### DR Region (us-west-2)

Warm standby environment ready for failover.

**Components:**
- **ECS Fargate**: Frontend and Backend services (auto-scaled 1-10 tasks)
- **RDS PostgreSQL**: Read replica (promoted during failover)
- **S3**: Replicated bucket (receives objects via CRR)
- **ALB**: Standby load balancer
- **ECR**: Replicated container images

## Data Flow

### Normal Operation
```
Users → Route53 → Primary ALB → ECS → RDS Primary
                                  ↓
                              S3 Primary
```

### During Failover
```
Users → Route53 → DR ALB → ECS → RDS (promoted)
                              ↓
                          S3 DR
```

## Network Architecture

Each region has:
- 1 VPC with /16 CIDR
- 2 Public Subnets (ALB)
- 2 Private Subnets (ECS, RDS)
- VPC Endpoints for AWS services (no NAT Gateway)

## Security

- All data encrypted at rest (RDS, S3, Secrets Manager)
- Private subnets for compute and database
- Security groups with least-privilege access
- Secrets stored in AWS Secrets Manager
