# Failback Runbook

## Overview

Failback returns operations from DR region (us-west-2) back to primary region (us-east-1) after the primary region has recovered.

> **Important:** Failback is more complex than failover because you need to re-establish replication before switching traffic.

## Prerequisites

- Primary region is healthy and accessible
- RDS in primary region is rebuilt or restored
- Replication is established from DR (current primary) to original primary
- Replication lag is near zero

## Preparation Phase

### 1. Verify Primary Region Health

```bash
# Check VPC and networking
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=dr-platform-primary*" --region us-east-1

# Check ECS cluster
aws ecs describe-clusters --clusters dr-platform-primary-cluster --region us-east-1
```

### 2. Rebuild Primary Database

If the primary database was destroyed:

```bash
# Create new RDS instance from DR snapshot
aws rds create-db-instance-read-replica \
  --db-instance-identifier dr-platform-primary-db \
  --source-db-instance-identifier arn:aws:rds:us-west-2:ACCOUNT_ID:db:dr-platform-dr-db \
  --region us-east-1
```

### 3. Wait for Replication Sync

```bash
# Monitor replication lag
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value=dr-platform-primary-db \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average \
  --region us-east-1
```

Wait until ReplicaLag is consistently < 5 seconds.

## Execution Phase

### Via Dashboard

1. Navigate to https://dashboard.my-projects-aws.site
2. Click "Initiate Failback"
3. Confirm replication status is healthy
4. Enter reason for failback
5. Confirm the action

### Via AWS CLI

```bash
# Start failback Step Function
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:us-east-2:ACCOUNT_ID:stateMachine:dr-platform-failback \
  --input '{"reason": "Primary recovered", "operator": "your-name"}' \
  --region us-east-2
```

## Failback Workflow

The Step Function performs:

1. **Pre-flight checks**
   - Verify primary region health
   - Verify replication lag < 5 seconds
   - Verify ECS cluster capacity

2. **Stop writes to DR** (now acting as primary)
   - Scale down DR ECS services

3. **Promote primary database**
   - Promote RDS read replica to standalone

4. **Scale up primary ECS**
   - Increase task count to production levels

5. **DNS cutover**
   - Update Route53 to point to primary ALB

6. **Validation**
   - Run smoke tests against primary
   - Verify application health

7. **Re-establish DR replication**
   - Create new read replica in DR region

8. **Scale down DR to standby**
   - Reduce DR ECS tasks to minimum

## Verification Steps

```bash
# Check application on primary
curl https://app.my-projects-aws.site/health

# Verify DNS points to primary
dig app.my-projects-aws.site

# Confirm ECS task counts
aws ecs describe-services \
  --cluster dr-platform-primary-cluster \
  --services dr-platform-frontend dr-platform-backend \
  --region us-east-1
```

## Post-Failback Actions

- [ ] Verify new DR replica is syncing
- [ ] Update incident ticket with recovery time
- [ ] Conduct post-mortem on original failure
- [ ] Verify weekly DR test schedule is active
- [ ] Review and update runbooks based on lessons learned
