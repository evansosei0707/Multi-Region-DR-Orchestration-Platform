"""
Health Checker Lambda Function
Monitors the health of primary and DR regions
"""
import os
import json
import boto3
from datetime import datetime, timezone
import urllib.request
import urllib.error

# Environment variables
PRIMARY_REGION = os.environ.get('PRIMARY_REGION', 'us-east-1')
DR_REGION = os.environ.get('DR_REGION', 'us-west-2')
PRIMARY_ALB_DNS = os.environ.get('PRIMARY_ALB_DNS', '')
DR_ALB_DNS = os.environ.get('DR_ALB_DNS', '')
DR_STATE_TABLE = os.environ.get('DR_STATE_TABLE', '')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')
PRIMARY_DB_IDENTIFIER = os.environ.get('PRIMARY_DB_IDENTIFIER', '')
DR_DB_IDENTIFIER = os.environ.get('DR_DB_IDENTIFIER', '')

# Initialize clients
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')


def check_alb_health(alb_dns: str, timeout: int = 5) -> dict:
    """Check if ALB is responding to health checks"""
    try:
        url = f"http://{alb_dns}/health"
        req = urllib.request.Request(url, method='GET')
        with urllib.request.urlopen(req, timeout=timeout) as response:
            status_code = response.status
            body = response.read().decode('utf-8')
            return {
                'healthy': status_code == 200,
                'status_code': status_code,
                'response': body[:500]  # Truncate response
            }
    except urllib.error.URLError as e:
        return {
            'healthy': False,
            'status_code': 0,
            'error': str(e)
        }
    except Exception as e:
        return {
            'healthy': False,
            'status_code': 0,
            'error': str(e)
        }


def check_rds_status(db_identifier: str, region: str) -> dict:
    """Check RDS instance status"""
    try:
        rds = boto3.client('rds', region_name=region)
        response = rds.describe_db_instances(DBInstanceIdentifier=db_identifier)
        
        if not response['DBInstances']:
            return {'healthy': False, 'status': 'NOT_FOUND'}
        
        instance = response['DBInstances'][0]
        status = instance['DBInstanceStatus']
        
        return {
            'healthy': status == 'available',
            'status': status,
            'endpoint': instance.get('Endpoint', {}).get('Address', 'N/A')
        }
    except Exception as e:
        return {
            'healthy': False,
            'status': 'ERROR',
            'error': str(e)
        }


def check_replication_lag(dr_db_identifier: str) -> dict:
    """Check RDS replication lag for read replica"""
    try:
        cloudwatch = boto3.client('cloudwatch', region_name=DR_REGION)
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/RDS',
            MetricName='ReplicaLag',
            Dimensions=[
                {'Name': 'DBInstanceIdentifier', 'Value': dr_db_identifier}
            ],
            StartTime=datetime.now(timezone.utc).replace(second=0, microsecond=0),
            EndTime=datetime.now(timezone.utc),
            Period=60,
            Statistics=['Average']
        )
        
        datapoints = response.get('Datapoints', [])
        if datapoints:
            lag = datapoints[-1].get('Average', 0)
            return {
                'healthy': lag < 60,  # Less than 60 seconds lag
                'lag_seconds': lag
            }
        return {
            'healthy': True,
            'lag_seconds': 0,
            'note': 'No datapoints available'
        }
    except Exception as e:
        return {
            'healthy': False,
            'lag_seconds': -1,
            'error': str(e)
        }


def update_dr_state(state_data: dict):
    """Update the DR state table in DynamoDB"""
    try:
        table = dynamodb.Table(DR_STATE_TABLE)
        timestamp = datetime.now(timezone.utc).isoformat()
        
        # Update health status
        table.put_item(Item={
            'state_key': 'health_status',
            'timestamp': timestamp,
            'primary_alb_healthy': state_data['primary_alb']['healthy'],
            'dr_alb_healthy': state_data['dr_alb']['healthy'],
            'primary_db_healthy': state_data['primary_db']['healthy'],
            'dr_db_healthy': state_data['dr_db']['healthy'],
            'replication_lag_seconds': state_data['replication'].get('lag_seconds', -1),
            'overall_healthy': state_data['overall_healthy'],
            'details': json.dumps(state_data)
        })
        
        # Update last check timestamp
        table.put_item(Item={
            'state_key': 'last_health_check',
            'timestamp': timestamp
        })
        
        return True
    except Exception as e:
        print(f"Error updating DR state: {e}")
        return False


def send_alert(subject: str, message: str):
    """Send alert via SNS"""
    try:
        if SNS_TOPIC_ARN:
            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject=subject[:100],  # SNS subject limit
                Message=message
            )
            print(f"Alert sent: {subject}")
    except Exception as e:
        print(f"Error sending alert: {e}")


def lambda_handler(event, context):
    """Main Lambda handler"""
    print(f"Health check started at {datetime.now(timezone.utc).isoformat()}")
    
    # Check all components
    primary_alb = check_alb_health(PRIMARY_ALB_DNS)
    dr_alb = check_alb_health(DR_ALB_DNS)
    primary_db = check_rds_status(PRIMARY_DB_IDENTIFIER, PRIMARY_REGION)
    dr_db = check_rds_status(DR_DB_IDENTIFIER, DR_REGION)
    replication = check_replication_lag(DR_DB_IDENTIFIER)
    
    # Determine overall health
    overall_healthy = (
        primary_alb['healthy'] and
        primary_db['healthy'] and
        dr_db['healthy'] and
        replication.get('healthy', True)
    )
    
    state_data = {
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'primary_alb': primary_alb,
        'dr_alb': dr_alb,
        'primary_db': primary_db,
        'dr_db': dr_db,
        'replication': replication,
        'overall_healthy': overall_healthy
    }
    
    # Update DynamoDB state
    update_dr_state(state_data)
    
    # Send alerts if unhealthy
    if not primary_alb['healthy']:
        send_alert(
            "🚨 DR Alert: Primary ALB Unhealthy",
            f"Primary ALB at {PRIMARY_ALB_DNS} is not responding.\n\n"
            f"Details: {json.dumps(primary_alb, indent=2)}\n\n"
            f"Consider initiating failover if issue persists."
        )
    
    if not primary_db['healthy']:
        send_alert(
            "🚨 DR Alert: Primary Database Unhealthy",
            f"Primary RDS instance {PRIMARY_DB_IDENTIFIER} is not healthy.\n\n"
            f"Status: {primary_db.get('status', 'UNKNOWN')}\n\n"
            f"Details: {json.dumps(primary_db, indent=2)}"
        )
    
    if replication.get('lag_seconds', 0) > 300:  # 5 minutes
        send_alert(
            "⚠️ DR Warning: High Replication Lag",
            f"Replication lag is {replication['lag_seconds']} seconds.\n\n"
            f"This exceeds the 5-minute warning threshold.\n"
            f"RPO may be at risk."
        )
    
    print(f"Health check completed. Overall healthy: {overall_healthy}")
    
    return {
        'statusCode': 200,
        'body': json.dumps(state_data, default=str)
    }
