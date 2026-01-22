# Failover Runbook

## Prerequisites

- Access to DR Dashboard at https://dashboard.my-projects-aws.site
- AWS CLI configured with appropriate permissions
- Understanding of RTO (5 min) and RPO (30 sec) targets

## Automated Failover

Automated failover is triggered when:
1. Route53 health check fails 3 consecutive times (90 seconds)
2. CloudWatch alarm triggers for application health

The Step Function automatically:
1. Validates DR region health
2. Stops primary ECS services (if reachable)
3. Promotes RDS replica in DR region
4. Scales up DR ECS services
5. Updates Route53 to point to DR ALB
6. Runs smoke tests
7. Sends SNS notification

## Manual Failover

### Via Dashboard

1. Navigate to https://dashboard.my-projects-aws.site
2. Click "Trigger Manual Failover"
3. Enter reason for failover
4. Confirm the action
5. Monitor progress in dashboard

### Via AWS CLI

```bash
# Start failover Step Function
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:us-east-2:ACCOUNT_ID:stateMachine:dr-platform-failover \
  --input '{"reason": "Manual failover", "operator": "your-name"}' \
  --region us-east-2
```

## Verification Steps

After failover completes:

1. **Check application access:**
   ```bash
   curl https://app.my-projects-aws.site/health
   ```

2. **Verify DNS resolution:**
   ```bash
   nslookup app.my-projects-aws.site
   # Should resolve to DR ALB IP
   ```

3. **Check database writes:**
   ```bash
   curl -X POST https://app.my-projects-aws.site/api/health-check
   ```

4. **Monitor CloudWatch metrics:**
   - ECS task count in DR region
   - ALB request count
   - Database connections

## Rollback

If failover fails mid-process:

1. Check Step Function execution for failed step
2. Review CloudWatch logs for errors
3. Manually complete remaining steps if needed
4. Consider immediate failback if primary recovers

## Post-Failover Actions

- [ ] Update incident ticket with failover time
- [ ] Notify stakeholders of DR activation
- [ ] Begin investigation of primary region failure
- [ ] Plan for failback when primary recovers
