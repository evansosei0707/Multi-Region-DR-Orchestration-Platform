"""
Failover Orchestrator Lambda Function
Executes the failover sequence from primary to DR region
"""
import os
import json
import boto3
import time
from datetime import datetime, timezone

# Environment variables
PRIMARY_REGION = os.environ.get('PRIMARY_REGION', 'us-east-1')
DR_REGION = os.environ.get('DR_REGION', 'us-west-2')
PRIMARY_DB_IDENTIFIER = os.environ.get('PRIMARY_DB_IDENTIFIER', '')
DR_DB_IDENTIFIER = os.environ.get('DR_DB_IDENTIFIER', '')
DR_ECS_CLUSTER = os.environ.get('DR_ECS_CLUSTER', '')
DR_BACKEND_SERVICE = os.environ.get('DR_BACKEND_SERVICE', '')
DR_FRONTEND_SERVICE = os.environ.get('DR_FRONTEND_SERVICE', '')
HOSTED_ZONE_ID = os.environ.get('HOSTED_ZONE_ID', '')
APP_DOMAIN = os.environ.get('APP_DOMAIN', '')
DR_ALB_DNS = os.environ.get('DR_ALB_DNS', '')
DR_ALB_ZONE_ID = os.environ.get('DR_ALB_ZONE_ID', '')
SSM_ACTIVE_REGION_PARAM = os.environ.get('SSM_ACTIVE_REGION_PARAM', '')
DR_STATE_TABLE = os.environ.get('DR_STATE_TABLE', '')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')

# Initialize clients
sns = boto3.client('sns')
dynamodb = boto3.resource('dynamodb')


def log_step(step_name: str, status: str, details: str = ""):
    """Log failover step to DynamoDB and console"""
    timestamp = datetime.now(timezone.utc).isoformat()
    print(f"[{timestamp}] {step_name}: {status} - {details}")
    
    try:
        table = dynamodb.Table(DR_STATE_TABLE)
        table.put_item(Item={
            'state_key': f'failover_step_{step_name}',
            'timestamp': timestamp,
            'status': status,
            'details': details
        })
    except Exception as e:
        print(f"Error logging step: {e}")


def promote_dr_database() -> dict:
    """Promote DR read replica to standalone instance"""
    log_step("promote_database", "STARTED", f"Promoting {DR_DB_IDENTIFIER}")
    
    try:
        rds = boto3.client('rds', region_name=DR_REGION)
        
        # Check current status
        response = rds.describe_db_instances(DBInstanceIdentifier=DR_DB_IDENTIFIER)
        instance = response['DBInstances'][0]
        
        # If it's a read replica, promote it
        if 'ReadReplicaSourceDBInstanceIdentifier' in instance:
            rds.promote_read_replica(
                DBInstanceIdentifier=DR_DB_IDENTIFIER,
                BackupRetentionPeriod=7
            )
            
            # Wait for promotion to complete
            log_step("promote_database", "IN_PROGRESS", "Waiting for promotion...")
            waiter = rds.get_waiter('db_instance_available')
            waiter.wait(
                DBInstanceIdentifier=DR_DB_IDENTIFIER,
                WaiterConfig={'Delay': 30, 'MaxAttempts': 40}
            )
            
            log_step("promote_database", "COMPLETED", "Database promoted successfully")
            return {'success': True, 'message': 'Database promoted'}
        else:
            log_step("promote_database", "SKIPPED", "Instance is already standalone")
            return {'success': True, 'message': 'Already standalone'}
            
    except Exception as e:
        log_step("promote_database", "FAILED", str(e))
        return {'success': False, 'error': str(e)}


def scale_dr_services(desired_count: int = 2) -> dict:
    """Scale up DR ECS services"""
    log_step("scale_services", "STARTED", f"Scaling to {desired_count} tasks")
    
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
        
        # Wait for services to stabilize
        log_step("scale_services", "IN_PROGRESS", "Waiting for services to stabilize...")
        waiter = ecs.get_waiter('services_stable')
        waiter.wait(
            cluster=DR_ECS_CLUSTER,
            services=[DR_BACKEND_SERVICE, DR_FRONTEND_SERVICE],
            WaiterConfig={'Delay': 15, 'MaxAttempts': 40}
        )
        
        log_step("scale_services", "COMPLETED", f"Services scaled to {desired_count}")
        return {'success': True, 'message': f'Scaled to {desired_count} tasks'}
        
    except Exception as e:
        log_step("scale_services", "FAILED", str(e))
        return {'success': False, 'error': str(e)}


def update_dns_to_dr() -> dict:
    """Update Route 53 DNS to point to DR region"""
    log_step("update_dns", "STARTED", f"Switching DNS to {DR_ALB_DNS}")
    
    try:
        route53 = boto3.client('route53')
        
        # Update the A record to point to DR ALB
        route53.change_resource_record_sets(
            HostedZoneId=HOSTED_ZONE_ID,
            ChangeBatch={
                'Comment': 'Failover to DR region',
                'Changes': [{
                    'Action': 'UPSERT',
                    'ResourceRecordSet': {
                        'Name': APP_DOMAIN,
                        'Type': 'A',
                        'AliasTarget': {
                            'HostedZoneId': DR_ALB_ZONE_ID,
                            'DNSName': DR_ALB_DNS,
                            'EvaluateTargetHealth': True
                        }
                    }
                }]
            }
        )
        
        log_step("update_dns", "COMPLETED", f"DNS updated to {DR_ALB_DNS}")
        return {'success': True, 'message': 'DNS updated to DR'}
        
    except Exception as e:
        log_step("update_dns", "FAILED", str(e))
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


def update_failover_state(status: str, details: dict):
    """Update overall failover state in DynamoDB"""
    try:
        table = dynamodb.Table(DR_STATE_TABLE)
        table.put_item(Item={
            'state_key': 'failover_state',
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'status': status,
            'active_region': DR_REGION if status == 'COMPLETED' else PRIMARY_REGION,
            'details': json.dumps(details, default=str)
        })
    except Exception as e:
        print(f"Error updating failover state: {e}")


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
    """Main Lambda handler for failover orchestration"""
    start_time = datetime.now(timezone.utc)
    print(f"Failover started at {start_time.isoformat()}")
    
    # Initialize results
    results = {
        'started_at': start_time.isoformat(),
        'steps': {}
    }
    
    # Send initial notification
    send_notification(
        "🔄 DR Failover Initiated",
        f"Failover to DR region ({DR_REGION}) has been initiated.\n\n"
        f"Start Time: {start_time.isoformat()}\n"
        f"Reason: {event.get('reason', 'Manual trigger')}"
    )
    
    update_failover_state('IN_PROGRESS', results)
    
    try:
        # Step 1: Scale up DR services
        results['steps']['scale_services'] = scale_dr_services(2)
        if not results['steps']['scale_services']['success']:
            raise Exception("Failed to scale DR services")
        
        # Step 2: Promote DR database (if it's a replica)
        results['steps']['promote_database'] = promote_dr_database()
        if not results['steps']['promote_database']['success']:
            raise Exception("Failed to promote database")
        
        # Step 3: Update DNS to DR
        results['steps']['update_dns'] = update_dns_to_dr()
        if not results['steps']['update_dns']['success']:
            raise Exception("Failed to update DNS")
        
        # Step 4: Update active region parameter
        results['steps']['update_active_region'] = update_active_region(DR_REGION)
        
        # Calculate duration
        end_time = datetime.now(timezone.utc)
        duration = (end_time - start_time).total_seconds()
        
        results['completed_at'] = end_time.isoformat()
        results['duration_seconds'] = duration
        results['status'] = 'COMPLETED'
        
        update_failover_state('COMPLETED', results)
        
        # Send success notification
        send_notification(
            "✅ DR Failover Completed Successfully",
            f"Failover to DR region ({DR_REGION}) completed.\n\n"
            f"Duration: {duration:.1f} seconds\n"
            f"Active Region: {DR_REGION}\n"
            f"Application URL: https://{APP_DOMAIN}\n\n"
            f"Details:\n{json.dumps(results['steps'], indent=2, default=str)}"
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps(results, default=str)
        }
        
    except Exception as e:
        results['status'] = 'FAILED'
        results['error'] = str(e)
        
        update_failover_state('FAILED', results)
        
        send_notification(
            "❌ DR Failover Failed",
            f"Failover to DR region ({DR_REGION}) FAILED.\n\n"
            f"Error: {str(e)}\n\n"
            f"Partial Results:\n{json.dumps(results, indent=2, default=str)}\n\n"
            f"MANUAL INTERVENTION REQUIRED!"
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps(results, default=str)
        }
