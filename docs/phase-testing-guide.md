# Multi-Region DR Platform - Phase Testing Guide

## Current Status: Phase 6-7 Complete ✅

This document provides manual testing procedures for verifying the DR platform.

---

## What's Deployed

### Infrastructure (Phases 1-5)
| Component | Primary (us-east-1) | DR (us-west-2) |
|-----------|---------------------|----------------|
| VPC | `vpc-0279957a2b5327d61` | `vpc-0440d31d28d6d7907` |
| RDS PostgreSQL | Primary instance | Read replica |
| ECS Cluster | 2 tasks (backend + frontend) | 1 task (warm standby) |
| ALB | `dr-platform-primary-alb-*` | `dr-platform-dr-alb-*` |
| ECR | Backend + Frontend images | Replicated |
| S3 | Primary bucket | Cross-region replicated |

### Control Plane (Phases 6-7)
| Component | Purpose |
|-----------|---------|
| Health Checker Lambda | Monitors ALB, RDS health every minute |
| Failover Orchestrator Lambda | Executes failover to DR region |
| Failback Orchestrator Lambda | Executes failback to primary |
| Step Functions | Orchestrated failover/failback workflows |
| DynamoDB | Stores DR state and health history |
| SSM Parameter | Tracks active region |
| SNS Topic | Sends DR alerts |
| EventBridge | Triggers health checks every minute |

---

## Quick Access URLs

```bash
# Primary Application
http://dr-platform-primary-alb-1609210064.us-east-1.elb.amazonaws.com

# DR Application (warm standby)
http://dr-platform-dr-alb-15096759.us-west-2.elb.amazonaws.com

# API Endpoints
http://dr-platform-primary-alb-1609210064.us-east-1.elb.amazonaws.com/api/products
http://dr-platform-primary-alb-1609210064.us-east-1.elb.amazonaws.com/health
```

---

## Manual Testing Procedures

### Test 1: Verify Application Health

```bash
# Test primary frontend
curl http://dr-platform-primary-alb-1609210064.us-east-1.elb.amazonaws.com

# Test primary API
curl http://dr-platform-primary-alb-1609210064.us-east-1.elb.amazonaws.com/api/products

# Test DR API (should also return products)
curl http://dr-platform-dr-alb-15096759.us-west-2.elb.amazonaws.com/api/products
```

**Expected:** Both regions return products from their respective databases.

---

### Test 2: Invoke Health Checker Lambda

```bash
# Manually trigger health check
aws lambda invoke \
  --function-name dr-platform-health-checker \
  --region us-east-2 \
  --payload '{}' \
  response.json && cat response.json | jq .
```

**Expected Output:**
```json
{
  "primary_alb": { "healthy": true },
  "dr_alb": { "healthy": true },
  "primary_db": { "healthy": true, "status": "available" },
  "dr_db": { "healthy": true, "status": "available" },
  "replication": { "healthy": true, "lag_seconds": 0 },
  "overall_healthy": true
}
```

---

### Test 3: Check DynamoDB State

```bash
# View health status in DynamoDB
aws dynamodb get-item \
  --table-name dr-platform-dr-state \
  --key '{"state_key": {"S": "health_status"}}' \
  --region us-east-2 \
  --output json | jq .

# Check active region
aws ssm get-parameter \
  --name /dr-platform/active-region \
  --region us-east-2 \
  --query 'Parameter.Value' \
  --output text
```

**Expected:** Active region shows `us-east-1` (primary).

---

### Test 4: View Step Functions

```bash
# List state machines
aws stepfunctions list-state-machines \
  --region us-east-2 \
  --query 'stateMachines[?contains(name, `dr-platform`)].[name]' \
  --output table
```

**Expected:** Shows `dr-platform-failover-workflow` and `dr-platform-failback-workflow`.

---

### Test 5: Check ECS Services

```bash
# Primary region services
aws ecs describe-services \
  --cluster dr-platform-primary-cluster \
  --services dr-platform-backend dr-platform-frontend \
  --region us-east-1 \
  --query 'services[].[serviceName,runningCount,desiredCount]' \
  --output table

# DR region services
aws ecs describe-services \
  --cluster dr-platform-dr-cluster \
  --services dr-platform-backend dr-platform-frontend \
  --region us-west-2 \
  --query 'services[].[serviceName,runningCount,desiredCount]' \
  --output table
```

**Expected:** Primary has 2 tasks each, DR has 1 task each.

---

### Test 6: Check RDS Replication

```bash
# Primary database status
aws rds describe-db-instances \
  --db-instance-identifier dr-platform-primary-db \
  --region us-east-1 \
  --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address]' \
  --output table

# DR replica status
aws rds describe-db-instances \
  --db-instance-identifier dr-platform-dr-replica \
  --region us-west-2 \
  --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address]' \
  --output table
```

**Expected:** Both show `available` status.

---

### Test 7: Simulate Failover (⚠️ Caution)

> **WARNING:** This will promote the DR database and switch traffic. Only run in test environments.

```bash
# Start failover workflow
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:us-east-2:235249476696:stateMachine:dr-platform-failover-workflow \
  --input '{"reason": "Manual test failover"}' \
  --region us-east-2

# Monitor execution
aws stepfunctions list-executions \
  --state-machine-arn arn:aws:states:us-east-2:235249476696:stateMachine:dr-platform-failover-workflow \
  --region us-east-2 \
  --query 'executions[0].[status,startDate]' \
  --output table
```

**After failover:**
- DR region becomes active
- DR database is promoted to standalone
- Active region parameter changes to `us-west-2`
- SNS notification sent

---

### Test 8: Simulate Failback (⚠️ Caution)

> **WARNING:** Only run after a failover test.

```bash
# Start failback workflow
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:us-east-2:235249476696:stateMachine:dr-platform-failback-workflow \
  --input '{"reason": "Manual test failback"}' \
  --region us-east-2
```

---

## CloudWatch Logs

```bash
# View health checker logs (use PowerShell or CMD to avoid Git Bash path issues)
aws logs tail /aws/lambda/dr-platform-health-checker --since 30m --region us-east-2

# View failover orchestrator logs
aws logs tail /aws/lambda/dr-platform-failover-orchestrator --since 30m --region us-east-2
```

---

## SNS Subscription

To receive DR alerts, subscribe to the SNS topic:

```bash
# Subscribe email
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-2:235249476696:dr-platform-dr-alerts \
  --protocol email \
  --notification-endpoint your-email@example.com \
  --region us-east-2
```

---

## Troubleshooting

### ALB Health Check Failing
The health checker calls `/health` on ALBs. If failing:
```bash
curl http://dr-platform-primary-alb-1609210064.us-east-1.elb.amazonaws.com/health
```

### Lambda Errors
Check CloudWatch logs for errors:
```bash
aws logs filter-log-events \
  --log-group-name /aws/lambda/dr-platform-health-checker \
  --filter-pattern "ERROR" \
  --region us-east-2
```

### Database Connection Issues
Verify security groups allow ECS to access RDS:
```bash
aws ec2 describe-security-groups \
  --group-ids sg-0633cde1b6d363142 \
  --region us-east-1 \
  --query 'SecurityGroups[0].IpPermissions'
```

---

## Next Steps

After verifying all tests pass:
- [ ] Phase 8: Implement DR test automation
- [ ] Phase 9: Add cost analytics (optional)
- [ ] Phase 10: Build DR dashboard
- [ ] Phase 11: Set up CI/CD pipeline
- [ ] Phase 12: Complete documentation
- [ ] Phase 13: Record demo video
