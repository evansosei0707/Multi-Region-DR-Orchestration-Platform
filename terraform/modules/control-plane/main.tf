# -----------------------------------------------------------------------------
# Control Plane Module - Placeholder
# This module will be fully implemented in Phase 6-7
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

variable "primary_db_identifier" {
  type = string
}

variable "dr_db_identifier" {
  type = string
}

variable "rto_target_minutes" {
  type = number
}

variable "rpo_target_seconds" {
  type = number
}

variable "sns_topic_arn" {
  type = string
}

# -----------------------------------------------------------------------------
# DynamoDB Table - DR State
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "dr_state" {
  name           = "${var.project_name}-dr-state"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "state_key"

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
  value = "us-east-1"  # Default to primary

  tags = {
    Name = "${var.project_name}-active-region"
  }

  lifecycle {
    ignore_changes = [value]
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "failover_state_machine_arn" {
  description = "Failover Step Function ARN (placeholder)"
  value       = "arn:aws:states:us-east-2:000000000000:stateMachine:placeholder"
}

output "dr_state_table_name" {
  description = "DynamoDB DR state table name"
  value       = aws_dynamodb_table.dr_state.name
}

output "active_region_parameter" {
  description = "SSM parameter for active region"
  value       = aws_ssm_parameter.active_region.name
}
