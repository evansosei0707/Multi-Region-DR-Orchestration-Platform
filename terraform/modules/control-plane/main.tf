# -----------------------------------------------------------------------------
# Control Plane Module - Full Implementation
# Route 53, Lambda, Step Functions, CloudWatch, SNS
# -----------------------------------------------------------------------------

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "primary_region" {
  type    = string
  default = "us-east-1"
}

variable "dr_region" {
  type    = string
  default = "us-west-2"
}

variable "primary_ecs_cluster_name" {
  type = string
}

variable "primary_ecs_frontend_service" {
  type = string
}

variable "primary_ecs_backend_service" {
  type = string
}

variable "primary_alb_arn" {
  type = string
}

variable "primary_alb_dns" {
  type = string
}

variable "primary_alb_zone_id" {
  type    = string
  default = "Z35SXDOTRQ7X7K"  # us-east-1 ALB hosted zone
}

variable "dr_ecs_cluster_name" {
  type = string
}

variable "dr_ecs_frontend_service" {
  type = string
}

variable "dr_ecs_backend_service" {
  type = string
}

variable "dr_alb_arn" {
  type = string
}

variable "dr_alb_dns" {
  type = string
}

variable "dr_alb_zone_id" {
  type    = string
  default = "Z1H1FL5HABSF5"  # us-west-2 ALB hosted zone
}

variable "primary_db_identifier" {
  type = string
}

variable "dr_db_identifier" {
  type = string
}

variable "rto_target_minutes" {
  type    = number
  default = 15
}

variable "rpo_target_seconds" {
  type    = number
  default = 60
}

variable "sns_topic_arn" {
  type    = string
  default = ""
}

variable "notification_email" {
  type    = string
  default = ""
}

# Get current region
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# SNS Topic for DR Notifications
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "dr_alerts" {
  name = "${var.project_name}-dr-alerts"

  tags = {
    Name = "${var.project_name}-dr-alerts"
  }
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.dr_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# -----------------------------------------------------------------------------
# DynamoDB Table - DR State
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "dr_state" {
  name         = "${var.project_name}-dr-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "state_key"

  attribute {
    name = "state_key"
    type = "S"
  }

  tags = {
    Name = "${var.project_name}-dr-state-table"
  }
}

# -----------------------------------------------------------------------------
# SSM Parameter - Active Region
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "active_region" {
  name  = "/${var.project_name}/active-region"
  type  = "String"
  value = var.primary_region

  tags = {
    Name = "${var.project_name}-active-region"
  }

  lifecycle {
    ignore_changes = [value]
  }
}

# -----------------------------------------------------------------------------
# Route 53 - Hosted Zone (use existing if domain is configured)
# -----------------------------------------------------------------------------

data "aws_route53_zone" "main" {
  count = var.domain_name != "" ? 1 : 0
  name  = var.domain_name
}

# Health Check - Primary ALB
resource "aws_route53_health_check" "primary_alb" {
  count             = var.domain_name != "" ? 1 : 0
  fqdn              = var.primary_alb_dns
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  failure_threshold = "3"
  request_interval  = "30"

  tags = {
    Name = "${var.project_name}-primary-alb-health"
  }
}

# Health Check - DR ALB
resource "aws_route53_health_check" "dr_alb" {
  count             = var.domain_name != "" ? 1 : 0
  fqdn              = var.dr_alb_dns
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  failure_threshold = "3"
  request_interval  = "30"

  tags = {
    Name = "${var.project_name}-dr-alb-health"
  }
}

# Primary A Record with failover routing
resource "aws_route53_record" "app_primary" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = "app.${var.domain_name}"
  type    = "A"

  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary_alb[0].id

  alias {
    name                   = var.primary_alb_dns
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }
}

# DR A Record with failover routing
resource "aws_route53_record" "app_dr" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = "app.${var.domain_name}"
  type    = "A"

  failover_routing_policy {
    type = "SECONDARY"
  }

  set_identifier  = "dr"
  health_check_id = aws_route53_health_check.dr_alb[0].id

  alias {
    name                   = var.dr_alb_dns
    zone_id                = var.dr_alb_zone_id
    evaluate_target_health = true
  }
}

# -----------------------------------------------------------------------------
# IAM Role for Lambda Functions
# -----------------------------------------------------------------------------

resource "aws_iam_role" "lambda_execution" {
  name = "${var.project_name}-dr-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-dr-lambda-role"
  }
}

resource "aws_iam_role_policy" "lambda_dr_policy" {
  name = "${var.project_name}-dr-lambda-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.dr_state.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.dr_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter"
        ]
        Resource = aws_ssm_parameter.active_region.arn
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:PromoteReadReplica"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:UpdateService"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:GetHealthCheck"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Lambda Functions
# -----------------------------------------------------------------------------

# Package Lambda functions
data "archive_file" "health_checker" {
  type        = "zip"
  source_file = "${path.module}/lambda/health_checker.py"
  output_path = "${path.module}/lambda/health_checker.zip"
}

data "archive_file" "failover_orchestrator" {
  type        = "zip"
  source_file = "${path.module}/lambda/failover_orchestrator.py"
  output_path = "${path.module}/lambda/failover_orchestrator.zip"
}

data "archive_file" "failback_orchestrator" {
  type        = "zip"
  source_file = "${path.module}/lambda/failback_orchestrator.py"
  output_path = "${path.module}/lambda/failback_orchestrator.zip"
}

# Health Checker Lambda
resource "aws_lambda_function" "health_checker" {
  filename         = data.archive_file.health_checker.output_path
  function_name    = "${var.project_name}-health-checker"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "health_checker.lambda_handler"
  source_code_hash = data.archive_file.health_checker.output_base64sha256
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      PRIMARY_REGION       = var.primary_region
      DR_REGION            = var.dr_region
      PRIMARY_ALB_DNS      = var.primary_alb_dns
      DR_ALB_DNS           = var.dr_alb_dns
      DR_STATE_TABLE       = aws_dynamodb_table.dr_state.name
      SNS_TOPIC_ARN        = aws_sns_topic.dr_alerts.arn
      PRIMARY_DB_IDENTIFIER = var.primary_db_identifier
      DR_DB_IDENTIFIER      = var.dr_db_identifier
    }
  }

  tags = {
    Name = "${var.project_name}-health-checker"
  }
}

# Failover Orchestrator Lambda
resource "aws_lambda_function" "failover_orchestrator" {
  filename         = data.archive_file.failover_orchestrator.output_path
  function_name    = "${var.project_name}-failover-orchestrator"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "failover_orchestrator.lambda_handler"
  source_code_hash = data.archive_file.failover_orchestrator.output_base64sha256
  runtime          = "python3.11"
  timeout          = 900  # 15 minutes for failover
  memory_size      = 256

  environment {
    variables = {
      PRIMARY_REGION          = var.primary_region
      DR_REGION               = var.dr_region
      PRIMARY_DB_IDENTIFIER   = var.primary_db_identifier
      DR_DB_IDENTIFIER        = var.dr_db_identifier
      DR_ECS_CLUSTER          = var.dr_ecs_cluster_name
      DR_BACKEND_SERVICE      = var.dr_ecs_backend_service
      DR_FRONTEND_SERVICE     = var.dr_ecs_frontend_service
      HOSTED_ZONE_ID          = var.domain_name != "" ? data.aws_route53_zone.main[0].zone_id : ""
      APP_DOMAIN              = var.domain_name != "" ? "app.${var.domain_name}" : ""
      DR_ALB_DNS              = var.dr_alb_dns
      DR_ALB_ZONE_ID          = var.dr_alb_zone_id
      SSM_ACTIVE_REGION_PARAM = aws_ssm_parameter.active_region.name
      DR_STATE_TABLE          = aws_dynamodb_table.dr_state.name
      SNS_TOPIC_ARN           = aws_sns_topic.dr_alerts.arn
    }
  }

  tags = {
    Name = "${var.project_name}-failover-orchestrator"
  }
}

# Failback Orchestrator Lambda
resource "aws_lambda_function" "failback_orchestrator" {
  filename         = data.archive_file.failback_orchestrator.output_path
  function_name    = "${var.project_name}-failback-orchestrator"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "failback_orchestrator.lambda_handler"
  source_code_hash = data.archive_file.failback_orchestrator.output_base64sha256
  runtime          = "python3.11"
  timeout          = 900  # 15 minutes for failback
  memory_size      = 256

  environment {
    variables = {
      PRIMARY_REGION            = var.primary_region
      DR_REGION                 = var.dr_region
      PRIMARY_DB_IDENTIFIER     = var.primary_db_identifier
      DR_DB_IDENTIFIER          = var.dr_db_identifier
      PRIMARY_ECS_CLUSTER       = var.primary_ecs_cluster_name
      PRIMARY_BACKEND_SERVICE   = var.primary_ecs_backend_service
      PRIMARY_FRONTEND_SERVICE  = var.primary_ecs_frontend_service
      DR_ECS_CLUSTER            = var.dr_ecs_cluster_name
      DR_BACKEND_SERVICE        = var.dr_ecs_backend_service
      DR_FRONTEND_SERVICE       = var.dr_ecs_frontend_service
      HOSTED_ZONE_ID            = var.domain_name != "" ? data.aws_route53_zone.main[0].zone_id : ""
      APP_DOMAIN                = var.domain_name != "" ? "app.${var.domain_name}" : ""
      PRIMARY_ALB_DNS           = var.primary_alb_dns
      PRIMARY_ALB_ZONE_ID       = var.primary_alb_zone_id
      SSM_ACTIVE_REGION_PARAM   = aws_ssm_parameter.active_region.name
      DR_STATE_TABLE            = aws_dynamodb_table.dr_state.name
      SNS_TOPIC_ARN             = aws_sns_topic.dr_alerts.arn
    }
  }

  tags = {
    Name = "${var.project_name}-failback-orchestrator"
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Event Rule - Health Checker Schedule
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "health_check_schedule" {
  name                = "${var.project_name}-health-check-schedule"
  description         = "Trigger health check every minute"
  schedule_expression = "rate(1 minute)"

  tags = {
    Name = "${var.project_name}-health-check-schedule"
  }
}

resource "aws_cloudwatch_event_target" "health_check" {
  rule      = aws_cloudwatch_event_rule.health_check_schedule.name
  target_id = "health-checker"
  arn       = aws_lambda_function.health_checker.arn
}

resource "aws_lambda_permission" "health_check_eventbridge" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.health_checker.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.health_check_schedule.arn
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms
# -----------------------------------------------------------------------------

# Alarm for primary ALB health check failures
resource "aws_cloudwatch_metric_alarm" "primary_alb_unhealthy" {
  count               = var.domain_name != "" ? 1 : 0
  alarm_name          = "${var.project_name}-primary-alb-unhealthy"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "Primary ALB health check is failing"

  dimensions = {
    HealthCheckId = aws_route53_health_check.primary_alb[0].id
  }

  alarm_actions = [aws_sns_topic.dr_alerts.arn]
  ok_actions    = [aws_sns_topic.dr_alerts.arn]

  tags = {
    Name = "${var.project_name}-primary-alb-alarm"
  }
}

# -----------------------------------------------------------------------------
# Step Functions - Failover State Machine
# -----------------------------------------------------------------------------

resource "aws_iam_role" "step_functions" {
  name = "${var.project_name}-step-functions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "states.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-step-functions-role"
  }
}

resource "aws_iam_role_policy" "step_functions_policy" {
  name = "${var.project_name}-step-functions-policy"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.health_checker.arn,
          aws_lambda_function.failover_orchestrator.arn,
          aws_lambda_function.failback_orchestrator.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.dr_alerts.arn
      }
    ]
  })
}

resource "aws_sfn_state_machine" "failover" {
  name     = "${var.project_name}-failover-workflow"
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "DR Failover Workflow"
    StartAt = "CheckPrimaryHealth"
    States = {
      CheckPrimaryHealth = {
        Type     = "Task"
        Resource = aws_lambda_function.health_checker.arn
        Next     = "EvaluateHealth"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "NotifyFailure"
        }]
      }
      EvaluateHealth = {
        Type = "Choice"
        Choices = [{
          Variable      = "$.body"
          StringMatches = "*\"overall_healthy\": true*"
          Next          = "PrimaryHealthy"
        }]
        Default = "InitiateFailover"
      }
      PrimaryHealthy = {
        Type = "Succeed"
      }
      InitiateFailover = {
        Type     = "Task"
        Resource = aws_lambda_function.failover_orchestrator.arn
        Next     = "FailoverComplete"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "NotifyFailure"
        }]
      }
      FailoverComplete = {
        Type = "Succeed"
      }
      NotifyFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.dr_alerts.arn
          Message  = "Failover workflow failed. Manual intervention required."
          Subject  = "❌ DR Failover Workflow Failed"
        }
        End = true
      }
    }
  })

  tags = {
    Name = "${var.project_name}-failover-workflow"
  }
}

resource "aws_sfn_state_machine" "failback" {
  name     = "${var.project_name}-failback-workflow"
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "DR Failback Workflow"
    StartAt = "InitiateFailback"
    States = {
      InitiateFailback = {
        Type     = "Task"
        Resource = aws_lambda_function.failback_orchestrator.arn
        Next     = "FailbackComplete"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "NotifyFailure"
        }]
      }
      FailbackComplete = {
        Type = "Succeed"
      }
      NotifyFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.dr_alerts.arn
          Message  = "Failback workflow failed. Manual intervention required."
          Subject  = "❌ DR Failback Workflow Failed"
        }
        End = true
      }
    }
  })

  tags = {
    Name = "${var.project_name}-failback-workflow"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "failover_state_machine_arn" {
  description = "Failover Step Function ARN"
  value       = aws_sfn_state_machine.failover.arn
}

output "failback_state_machine_arn" {
  description = "Failback Step Function ARN"
  value       = aws_sfn_state_machine.failback.arn
}

output "dr_state_table_name" {
  description = "DynamoDB DR state table name"
  value       = aws_dynamodb_table.dr_state.name
}

output "active_region_parameter" {
  description = "SSM parameter for active region"
  value       = aws_ssm_parameter.active_region.name
}

output "health_checker_function_name" {
  description = "Health checker Lambda function name"
  value       = aws_lambda_function.health_checker.function_name
}

output "sns_topic_arn" {
  description = "SNS topic ARN for DR alerts"
  value       = aws_sns_topic.dr_alerts.arn
}

output "primary_health_check_id" {
  description = "Route 53 health check ID for primary ALB"
  value       = var.domain_name != "" ? aws_route53_health_check.primary_alb[0].id : ""
}

output "dr_health_check_id" {
  description = "Route 53 health check ID for DR ALB"
  value       = var.domain_name != "" ? aws_route53_health_check.dr_alb[0].id : ""
}
