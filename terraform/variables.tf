# -----------------------------------------------------------------------------
# Project Configuration
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "dr-platform"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "domain_name" {
  description = "Root domain name"
  type        = string
  default     = "my-projects-aws.site"
}

# -----------------------------------------------------------------------------
# Database Initialization (Temporary)
# -----------------------------------------------------------------------------

variable "enable_db_bastion_access" {
  description = "Enable temporary access to RDS from specific IP for initialization"
  type        = bool
  default     = false
}

variable "bastion_ip_cidr" {
  description = "IP CIDR to allow temporary RDS access (e.g., your IP/32 or CloudShell IP/32)"
  type        = string
  default     = "0.0.0.0/32"  # Invalid default - must be set explicitly
}

# -----------------------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------------------

variable "control_plane_vpc_cidr" {
  description = "CIDR block for control plane VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "primary_vpc_cidr" {
  description = "CIDR block for primary region VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "dr_vpc_cidr" {
  description = "CIDR block for DR region VPC"
  type        = string
  default     = "10.2.0.0/16"
}

# -----------------------------------------------------------------------------
# Database Configuration
# -----------------------------------------------------------------------------

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "14.20"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Name of the database"
  type        = string
  default     = "ecommerce"
}

# -----------------------------------------------------------------------------
# ECS Configuration
# -----------------------------------------------------------------------------

variable "ecs_frontend_cpu" {
  description = "Frontend task CPU units"
  type        = number
  default     = 256
}

variable "ecs_frontend_memory" {
  description = "Frontend task memory in MB"
  type        = number
  default     = 512
}

variable "ecs_backend_cpu" {
  description = "Backend task CPU units"
  type        = number
  default     = 256
}

variable "ecs_backend_memory" {
  description = "Backend task memory in MB"
  type        = number
  default     = 512
}

variable "primary_min_tasks" {
  description = "Minimum ECS tasks in primary region"
  type        = number
  default     = 2
}

variable "primary_max_tasks" {
  description = "Maximum ECS tasks in primary region"
  type        = number
  default     = 10
}

variable "dr_min_tasks" {
  description = "Minimum ECS tasks in DR region (warm standby)"
  type        = number
  default     = 1
}

variable "dr_max_tasks" {
  description = "Maximum ECS tasks in DR region"
  type        = number
  default     = 10
}

# -----------------------------------------------------------------------------
# DR Configuration
# -----------------------------------------------------------------------------

variable "rto_target_minutes" {
  description = "Recovery Time Objective in minutes"
  type        = number
  default     = 5
}

variable "rpo_target_seconds" {
  description = "Recovery Point Objective for database in seconds"
  type        = number
  default     = 30
}

variable "replication_lag_alarm_threshold" {
  description = "RDS replication lag alarm threshold in seconds"
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Notification Configuration
# -----------------------------------------------------------------------------

variable "notification_email" {
  description = "Email address for DR notifications"
  type        = string
  default     = ""
}
