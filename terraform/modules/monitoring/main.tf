# -----------------------------------------------------------------------------
# Monitoring Module - SNS Topic for Alerts
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "notification_email" {
  description = "Email address for notifications"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# SNS Topic for DR Alerts
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "dr_alerts" {
  name = "${var.project_name}-${var.environment}-dr-alerts"

  tags = {
    Name = "${var.project_name}-${var.environment}-dr-alerts"
  }
}

# Email Subscription (optional)
resource "aws_sns_topic_subscription" "email" {
  count = var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.dr_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "dr_alerts" {
  arn = aws_sns_topic.dr_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarms"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.dr_alerts.arn
      },
      {
        Sid    = "AllowEventBridge"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.dr_alerts.arn
      },
      {
        Sid    = "AllowLambda"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.dr_alerts.arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "sns_topic_arn" {
  description = "SNS Topic ARN for alerts"
  value       = aws_sns_topic.dr_alerts.arn
}

output "sns_topic_name" {
  description = "SNS Topic name"
  value       = aws_sns_topic.dr_alerts.name
}
