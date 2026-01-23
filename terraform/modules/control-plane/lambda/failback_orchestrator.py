"""
Failback Orchestrator Lambda Function
Executes the failback sequence from DR back to primary region
"""
import os
import json
import boto3
from datetime import datetime, timezone

# Environment variables
PRIMARY_REGION = os.environ.get('PRIMARY_REGION', 'us-east-1')
DR_REGION = os.environ.get('DR_REGION', 'us-west-2')
PRIMARY_DB_IDENTIFIER = os.environ.get('PRIMARY_DB_IDENTIFIER', '')
DR_DB_IDENTIFIER = os.environ.get('DR_DB_IDENTIFIER', '')
PRIMARY_ECS_CLUSTER = os.environ.get('PRIMARY_ECS_CLUSTER', '')
PRIMARY_BACKEND_SERVICE = os.environ.get('PRIMARY_BACKEND_SERVICE', '')
PRIMARY_FRONTEND_SERVICE = os.environ.get('PRIMARY_FRONTEND_SERVICE', '')
DR_ECS_CLUSTER = os.environ.get('DR_ECS_CLUSTER', '')
DR_BACKEND_SERVICE = os.environ.get('DR_BACKEND_SERVICE', '')
DR_FRONTEND_SERVICE = os.environ.get('DR_FRONTEND_SERVICE', '')
HOSTED_ZONE_ID = os.environ.get('HOSTED_ZONE_ID', '')
APP_DOMAIN = os.environ.get('APP_DOMAIN', '')
PRIMARY_ALB_DNS = os.environ.get('PRIMARY_ALB_DNS', '')
PRIMARY_ALB_ZONE_ID = os.environ.get('PRIMARY_ALB_ZONE_ID', '')
SSM_ACTIVE_REGION_PARAM = os.environ.get('SSM_ACTIVE_REGION_PARAM', '')
DR_STATE_TABLE = os.environ.get('DR_STATE_TABLE', '')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')

# Initialize clients
sns = boto3.client('sns')
dynamodb = boto3.resource('dynamodb')


def log_step(step_name: str, status: str, details: str = ""):
    """Log failback step to DynamoDB and console"""
    timestamp = datetime.now(timezone.utc).isoformat()
    print(f"[{timestamp}] {step_name}: {status} - {details}")
    
    try:
        table = dynamodb.Table(DR_STATE_TABLE)
        table.put_item(Item={
            'state_key': f'failback_step_{step_name}',
            'timestamp': timestamp,
            'status': status,
            'details': details
        })
    except Exception as e:
        print(f"Error logging step: {e}")


def verify_primary_health() -> dict:
    """Verify primary region is healthy before failback"""
    log_step("verify_primary", "STARTED", "Checking primary region health")
    
    try:
        # Check primary RDS
        rds = boto3.client('rds', region_name=PRIMARY_REGION)
        response = rds.describe_db_instances(DBInstanceIdentifier=PRIMARY_DB_IDENTIFIER)
        
        if not response['DBInstances']:
            log_step("verify_primary", "FAILED", "Primary DB not found")
            return {'success': False, 'error': 'Primary DB not found'}
        
        db_status = response['DBInstances'][0]['DBInstanceStatus']
        if db_status != 'available':
            log_step("verify_primary", "FAILED", f"Primary DB status: {db_status}")
            return {'success': False, 'error': f'Primary DB not available: {db_status}'}
        
        # Check primary ECS
        ecs = boto3.client('ecs', region_name=PRIMARY_REGION)
        services = ecs.describe_services(
            cluster=PRIMARY_ECS_CLUSTER,
            services=[PRIMARY_BACKEND_SERVICE, PRIMARY_FRONTEND_SERVICE]
        )
        
        for service in services['services']:
            if service['runningCount'] < 1:
                log_step("verify_primary", "FAILED", f"Service {service['serviceName']} has no running tasks")
                return {'success': False, 'error': f"Service {service['serviceName']} not running"}
        
        log_step("verify_primary", "COMPLETED", "Primary region is healthy")
        return {'success': True, 'message': 'Primary region healthy'}
        
    except Exception as e:
        log_step("verify_primary", "FAILED", str(e))
        return {'success': False, 'error': str(e)}


def update_dns_to_primary() -> dict:
    """Update Route 53 DNS to point back to primary region"""
    log_step("update_dns", "STARTED", f"Switching DNS to {PRIMARY_ALB_DNS}")
    
    try:
        route53 = boto3.client('route53')
        
        # Update the A record to point to primary ALB
        route53.change_resource_record_sets(
            HostedZoneId=HOSTED_ZONE_ID,
            ChangeBatch={
                'Comment': 'Failback to primary region',
                'Changes': [{
                    'Action': 'UPSERT',
                    'ResourceRecordSet': {
                        'Name': APP_DOMAIN,
                        'Type': 'A',
                        'AliasTarget': {
                            'HostedZoneId': PRIMARY_ALB_ZONE_ID,
                            'DNSName': PRIMARY_ALB_DNS,
                            'EvaluateTargetHealth': True
                        }
                    }
                }]
            }
        )
        
        log_step("update_dns", "COMPLETED", f"DNS updated to {PRIMARY_ALB_DNS}")
        return {'success': True, 'message': 'DNS updated to primary'}
        
    except Exception as e:
        log_step("update_dns", "FAILED", str(e))
        return {'success': False, 'error': str(e)}


def scale_dr_services(desired_count: int = 1) -> dict:
    """Scale down DR ECS services to warm standby"""
    log_step("scale_dr_down", "STARTED", f"Scaling DR to {desired_count} tasks")
    
    try:
        ecs = boto3.client('ecs', region_name=DR_REGION)
        
        # Scale backend
        ecs.update_service(
            cluster=DR_ECS_CLUSTER,
            service=DR_BACKEND_SERVICE,
            desiredCount=desired_count
        )
        
        # Scale frontend
        ecs.update_service(
            cluster=DR_ECS_CLUSTER,
            service=DR_FRONTEND_SERVICE,
            desiredCount=desired_count
        )
        
        log_step("scale_dr_down", "COMPLETED", f"DR scaled to {desired_count}")
        return {'success': True, 'message': f'DR scaled to {desired_count} tasks'}
        
    except Exception as e:
        log_step("scale_dr_down", "FAILED", str(e))
        return {'success': False, 'error': str(e)}


def update_active_region(region: str) -> dict:
    """Update SSM parameter for active region"""
    log_step("update_ssm", "STARTED", f"Setting active region to {region}")
    
    try:
        ssm = boto3.client('ssm', region_name=PRIMARY_REGION)
        ssm.put_parameter(
            Name=SSM_ACTIVE_REGION_PARAM,
            Value=region,
            Type='String',
            Overwrite=True
        )
        
        log_step("update_ssm", "COMPLETED", f"Active region set to {region}")
        return {'success': True, 'message': f'Active region: {region}'}
        
    except Exception as e:
        log_step("update_ssm", "FAILED", str(e))
        return {'success': False, 'error': str(e)}


def recreate_replication() -> dict:
    """Recreate read replica from primary (placeholder - manual step in production)"""
    log_step("recreate_replication", "INFO", "Replication must be recreated manually")
    
    # Note: Recreating a read replica after promotion requires:
    # 1. Creating a new read replica from the primary
    # 2. This is typically done after data sync is confirmed
    # For now, we log this as a manual step
    
    return {
        'success': True,
        'message': 'Replication needs manual recreation',
        'action_required': 'Create new read replica from primary database'
    }


def update_failback_state(status: str, details: dict):
    """Update overall failback state in DynamoDB"""
    try:
        table = dynamodb.Table(DR_STATE_TABLE)
        table.put_item(Item={
            'state_key': 'failback_state',
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'status': status,
            'active_region': PRIMARY_REGION if status == 'COMPLETED' else DR_REGION,
            'details': json.dumps(details, default=str)
        })
    except Exception as e:
        print(f"Error updating failback state: {e}")


def send_notification(subject: str, message: str):
    """Send SNS notification"""
    try:
        if SNS_TOPIC_ARN:
            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject=subject[:100],
                Message=message
            )
    except Exception as e:
        print(f"Error sending notification: {e}")


def lambda_handler(event, context):
    """Main Lambda handler for failback orchestration"""
    start_time = datetime.now(timezone.utc)
    print(f"Failback started at {start_time.isoformat()}")
    
    # Initialize results
    results = {
        'started_at': start_time.isoformat(),
        'steps': {}
    }
    
    # Send initial notification
    send_notification(
        "🔄 DR Failback Initiated",
        f"Failback to primary region ({PRIMARY_REGION}) has been initiated.\n\n"
        f"Start Time: {start_time.isoformat()}\n"
        f"Reason: {event.get('reason', 'Manual trigger')}"
    )
    
    update_failback_state('IN_PROGRESS', results)
    
    try:
        # Step 1: Verify primary region is healthy
        results['steps']['verify_primary'] = verify_primary_health()
        if not results['steps']['verify_primary']['success']:
            raise Exception("Primary region not healthy for failback")
        
        # Step 2: Update DNS to primary
        results['steps']['update_dns'] = update_dns_to_primary()
        if not results['steps']['update_dns']['success']:
            raise Exception("Failed to update DNS")
        
        # Step 3: Update active region parameter
        results['steps']['update_active_region'] = update_active_region(PRIMARY_REGION)
        
        # Step 4: Scale down DR services
        results['steps']['scale_dr_down'] = scale_dr_services(1)
        
        # Step 5: Note about replication
        results['steps']['recreate_replication'] = recreate_replication()
        
        # Calculate duration
        end_time = datetime.now(timezone.utc)
        duration = (end_time - start_time).total_seconds()
        
        results['completed_at'] = end_time.isoformat()
        results['duration_seconds'] = duration
        results['status'] = 'COMPLETED'
        
        update_failback_state('COMPLETED', results)
        
        # Send success notification
        send_notification(
            "✅ DR Failback Completed Successfully",
            f"Failback to primary region ({PRIMARY_REGION}) completed.\n\n"
            f"Duration: {duration:.1f} seconds\n"
            f"Active Region: {PRIMARY_REGION}\n"
            f"Application URL: https://{APP_DOMAIN}\n\n"
            f"⚠️ ACTION REQUIRED:\n"
            f"Recreate DR read replica from primary database.\n\n"
            f"Details:\n{json.dumps(results['steps'], indent=2, default=str)}"
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps(results, default=str)
        }
        
    except Exception as e:
        results['status'] = 'FAILED'
        results['error'] = str(e)
        
        update_failback_state('FAILED', results)
        
        send_notification(
            "❌ DR Failback Failed",
            f"Failback to primary region ({PRIMARY_REGION}) FAILED.\n\n"
            f"Error: {str(e)}\n\n"
            f"Partial Results:\n{json.dumps(results, indent=2, default=str)}\n\n"
            f"MANUAL INTERVENTION REQUIRED!"
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps(results, default=str)
        }
