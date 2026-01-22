# -----------------------------------------------------------------------------
# Compute Module - Variables
# -----------------------------------------------------------------------------

variable "region_name" {
  description = "Name identifier for this region"
  type        = string
}

variable "region_type" {
  description = "Type of region (primary or dr)"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID for ALB"
  type        = string
}

variable "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "frontend_cpu" {
  description = "Frontend task CPU units"
  type        = number
  default     = 256
}

variable "frontend_memory" {
  description = "Frontend task memory in MB"
  type        = number
  default     = 512
}

variable "backend_cpu" {
  description = "Backend task CPU units"
  type        = number
  default     = 256
}

variable "backend_memory" {
  description = "Backend task memory in MB"
  type        = number
  default     = 512
}

variable "min_tasks" {
  description = "Minimum number of tasks"
  type        = number
}

variable "max_tasks" {
  description = "Maximum number of tasks"
  type        = number
}

variable "db_secret_arn" {
  description = "ARN of database credentials secret"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name for application"
  type        = string
}
