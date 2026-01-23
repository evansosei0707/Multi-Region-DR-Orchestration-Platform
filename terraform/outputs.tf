# -----------------------------------------------------------------------------
# Networking Outputs
# -----------------------------------------------------------------------------

output "control_plane_vpc_id" {
  description = "Control plane VPC ID"
  value       = module.networking_control_plane.vpc_id
}

output "primary_vpc_id" {
  description = "Primary region VPC ID"
  value       = module.networking_primary.vpc_id
}

output "dr_vpc_id" {
  description = "DR region VPC ID"
  value       = module.networking_dr.vpc_id
}

# -----------------------------------------------------------------------------
# Database Outputs
# -----------------------------------------------------------------------------

output "primary_db_endpoint" {
  description = "Primary RDS endpoint"
  value       = module.database_primary.db_endpoint
}

output "dr_db_endpoint" {
  description = "DR RDS replica endpoint"
  value       = module.database_dr.db_endpoint
}

# -----------------------------------------------------------------------------
# Application Outputs
# -----------------------------------------------------------------------------

output "primary_alb_dns" {
  description = "Primary ALB DNS name"
  value       = module.compute_primary.alb_dns_name
}

output "dr_alb_dns" {
  description = "DR ALB DNS name"
  value       = module.compute_dr.alb_dns_name
}

output "app_url" {
  description = "E-commerce application URL"
  value       = "https://app.${var.domain_name}"
}

output "dashboard_url" {
  description = "DR Dashboard URL"
  value       = "https://dashboard.${var.domain_name}"
}

# -----------------------------------------------------------------------------
# ECR Outputs
# -----------------------------------------------------------------------------

output "frontend_ecr_primary" {
  description = "Frontend ECR repository URL (primary)"
  value       = module.compute_primary.frontend_ecr_url
}

output "backend_ecr_primary" {
  description = "Backend ECR repository URL (primary)"
  value       = module.compute_primary.backend_ecr_url
}

# -----------------------------------------------------------------------------
# Control Plane Outputs
# -----------------------------------------------------------------------------

output "failover_state_machine_arn" {
  description = "Failover Step Function ARN"
  value       = module.control_plane.failover_state_machine_arn
}

output "failback_state_machine_arn" {
  description = "Failback Step Function ARN"
  value       = module.control_plane.failback_state_machine_arn
}

output "dr_state_table" {
  description = "DynamoDB table for DR state"
  value       = module.control_plane.dr_state_table_name
}

output "health_checker_function" {
  description = "Health checker Lambda function name"
  value       = module.control_plane.health_checker_function_name
}

output "sns_alerts_topic" {
  description = "SNS topic ARN for DR alerts"
  value       = module.control_plane.sns_topic_arn
}

output "active_region_parameter" {
  description = "SSM parameter for active region"
  value       = module.control_plane.active_region_parameter
}
