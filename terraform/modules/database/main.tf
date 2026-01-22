# -----------------------------------------------------------------------------
# Database Module - RDS PostgreSQL (Primary or Replica)
# -----------------------------------------------------------------------------

variable "region_name" {
  description = "Name identifier for this region"
  type        = string
}

variable "is_primary" {
  description = "Whether this is the primary database (true) or replica (false)"
  type        = bool
  default     = true
}

variable "source_db_instance_arn" {
  description = "ARN of source database for replica (required if is_primary = false)"
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "14.10"
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Name of the database"
  type        = string
  default     = "ecommerce"
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "rds_security_group_id" {
  description = "Security group ID for RDS"
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  type        = string
}

variable "replication_lag_threshold" {
  description = "Replication lag alarm threshold in seconds"
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------
# Random Password for Database
# -----------------------------------------------------------------------------

resource "random_password" "db_password" {
  count = var.is_primary ? 1 : 0

  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# -----------------------------------------------------------------------------
# DB Subnet Group
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.region_name}-db-subnet"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-${var.region_name}-db-subnet-group"
  }
}

# -----------------------------------------------------------------------------
# DB Parameter Group
# -----------------------------------------------------------------------------

resource "aws_db_parameter_group" "main" {
  name   = "${var.project_name}-${var.region_name}-pg14"
  family = "postgres14"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = {
    Name = "${var.project_name}-${var.region_name}-params"
  }
}

# -----------------------------------------------------------------------------
# Primary RDS Instance
# -----------------------------------------------------------------------------

resource "aws_db_instance" "primary" {
  count = var.is_primary ? 1 : 0

  identifier = "${var.project_name}-${var.region_name}-db"

  # Engine
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Storage
  allocated_storage     = var.allocated_storage
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database
  db_name  = var.db_name
  username = "dbadmin"
  password = random_password.db_password[0].result

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_security_group_id]
  publicly_accessible    = false

  # Backup
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  # Logging
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # High Availability
  multi_az = false  # Set to false to save costs, true for production

  # Parameter Group
  parameter_group_name = aws_db_parameter_group.main.name

  # Deletion
  deletion_protection       = false  # Set to true for production
  skip_final_snapshot       = true   # Set to false for production
  final_snapshot_identifier = "${var.project_name}-${var.region_name}-final"

  # Upgrades
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false

  tags = {
    Name = "${var.project_name}-${var.region_name}-primary-db"
    Role = "primary"
  }
}

# -----------------------------------------------------------------------------
# Data Source - Get AWS managed RDS KMS key for this region
# -----------------------------------------------------------------------------

data "aws_kms_key" "rds" {
  count = var.is_primary ? 0 : 1  # Only needed for replica
  
  key_id = "alias/aws/rds"
}

# -----------------------------------------------------------------------------
# Read Replica (DR Region)
# -----------------------------------------------------------------------------

resource "aws_db_instance" "replica" {
  count = var.is_primary ? 0 : 1

  identifier = "${var.project_name}-${var.region_name}-replica"

  # Replication source
  replicate_source_db = var.source_db_instance_arn

  # Instance (inherits engine from source)
  instance_class = var.instance_class

  # Storage - Must specify KMS key for cross-region encrypted replica
  storage_encrypted = true
  kms_key_id        = data.aws_kms_key.rds[0].arn

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_security_group_id]
  publicly_accessible    = false

  # Backup (replicas can have their own backup)
  backup_retention_period = 7

  # Logging
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # High Availability for replica
  multi_az = false

  # Parameter Group
  parameter_group_name = aws_db_parameter_group.main.name

  # Upgrades
  auto_minor_version_upgrade = true

  # Deletion
  deletion_protection = false
  skip_final_snapshot = true

  tags = {
    Name = "${var.project_name}-${var.region_name}-replica-db"
    Role = "replica"
  }
}

# -----------------------------------------------------------------------------
# Secrets Manager - Store Database Credentials
# -----------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "db_credentials" {
  name = "${var.project_name}-${var.region_name}-db-credentials"

  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.region_name}-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = var.is_primary ? "dbadmin" : "dbadmin"
    password = var.is_primary ? random_password.db_password[0].result : "replica-uses-source-password"
    engine   = "postgres"
    host     = var.is_primary ? aws_db_instance.primary[0].address : aws_db_instance.replica[0].address
    port     = 5432
    dbname   = var.db_name
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Alarm - Replication Lag (DR only)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  count = var.is_primary ? 0 : 1

  alarm_name          = "${var.project_name}-${var.region_name}-replication-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ReplicaLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = var.replication_lag_threshold
  alarm_description   = "RDS replica lag exceeds ${var.replication_lag_threshold} seconds"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.replica[0].identifier
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = {
    Name = "${var.project_name}-${var.region_name}-replication-lag-alarm"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "db_instance_id" {
  description = "Database instance identifier"
  value       = var.is_primary ? aws_db_instance.primary[0].identifier : aws_db_instance.replica[0].identifier
}

output "db_endpoint" {
  description = "Database endpoint"
  value       = var.is_primary ? aws_db_instance.primary[0].endpoint : aws_db_instance.replica[0].endpoint
}

output "db_address" {
  description = "Database address (hostname only)"
  value       = var.is_primary ? aws_db_instance.primary[0].address : aws_db_instance.replica[0].address
}

output "db_arn" {
  description = "Database ARN"
  value       = var.is_primary ? aws_db_instance.primary[0].arn : aws_db_instance.replica[0].arn
}

output "secret_arn" {
  description = "Secrets Manager secret ARN"
  value       = aws_secretsmanager_secret.db_credentials.arn
}
