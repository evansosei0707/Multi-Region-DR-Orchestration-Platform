# -----------------------------------------------------------------------------
# Main Terraform Configuration
# Multi-Region DR Orchestration Platform
# -----------------------------------------------------------------------------

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Get available AZs in each region
data "aws_availability_zones" "control_plane" {
  provider = aws.control_plane
  state    = "available"
}

data "aws_availability_zones" "primary" {
  provider = aws.primary
  state    = "available"
}

data "aws_availability_zones" "dr" {
  provider = aws.dr
  state    = "available"
}

# -----------------------------------------------------------------------------
# Networking - Control Plane (us-east-2)
# -----------------------------------------------------------------------------

module "networking_control_plane" {
  source = "./modules/networking"

  providers = {
    aws = aws.control_plane
  }

  region_name        = "control-plane"
  vpc_cidr           = var.control_plane_vpc_cidr
  availability_zones = slice(data.aws_availability_zones.control_plane.names, 0, 2)
  project_name       = var.project_name
  environment        = var.environment

  # Control plane doesn't need RDS, so no replication settings
  enable_rds_security_group = false
}

# -----------------------------------------------------------------------------
# Networking - Primary Region (us-east-1)
# -----------------------------------------------------------------------------

module "networking_primary" {
  source = "./modules/networking"

  providers = {
    aws = aws.primary
  }

  region_name        = "primary"
  vpc_cidr           = var.primary_vpc_cidr
  availability_zones = slice(data.aws_availability_zones.primary.names, 0, 2)
  project_name       = var.project_name
  environment        = var.environment

  enable_rds_security_group = true
  
  # Bastion access for database initialization
  enable_db_bastion_access = var.enable_db_bastion_access
  bastion_ip_cidr          = var.bastion_ip_cidr
}

# -----------------------------------------------------------------------------
# Networking - DR Region (us-west-2)
# -----------------------------------------------------------------------------

module "networking_dr" {
  source = "./modules/networking"

  providers = {
    aws = aws.dr
  }

  region_name        = "dr"
  vpc_cidr           = var.dr_vpc_cidr
  availability_zones = slice(data.aws_availability_zones.dr.names, 0, 2)
  project_name       = var.project_name
  environment        = var.environment

  enable_rds_security_group = true
  
  # Allow replication from primary region
  allow_rds_replication   = true
  primary_vpc_cidr        = var.primary_vpc_cidr
}

# -----------------------------------------------------------------------------
# Database - Primary Region (us-east-1)
# -----------------------------------------------------------------------------

module "database_primary" {
  source = "./modules/database"

  providers = {
    aws = aws.primary
  }

  region_name          = "primary"
  is_primary           = true
  project_name         = var.project_name
  environment          = var.environment
  
  # Instance configuration
  instance_class       = var.db_instance_class
  engine_version       = var.db_engine_version
  allocated_storage    = var.db_allocated_storage
  db_name              = var.db_name
  
  # Network
  private_subnet_ids   = module.networking_primary.private_subnet_ids
  rds_security_group_id = module.networking_primary.rds_security_group_id
  
  # Monitoring
  sns_topic_arn        = module.monitoring_primary.sns_topic_arn

  depends_on = [module.networking_primary]
}

# -----------------------------------------------------------------------------
# Database - DR Region (us-west-2) - Read Replica
# -----------------------------------------------------------------------------

module "database_dr" {
  source = "./modules/database"

  providers = {
    aws = aws.dr
  }

  region_name           = "dr"
  is_primary            = false
  source_db_instance_arn = module.database_primary.db_arn
  project_name          = var.project_name
  environment           = var.environment
  
  # Instance configuration
  instance_class        = var.db_instance_class
  
  # Network
  private_subnet_ids    = module.networking_dr.private_subnet_ids
  rds_security_group_id = module.networking_dr.rds_security_group_id
  
  # Monitoring
  sns_topic_arn         = module.monitoring_dr.sns_topic_arn
  replication_lag_threshold = var.replication_lag_alarm_threshold

  depends_on = [module.database_primary, module.networking_dr]
}

# -----------------------------------------------------------------------------
# Storage - S3 with Cross-Region Replication
# -----------------------------------------------------------------------------

module "storage" {
  source = "./modules/storage"

  providers = {
    aws.primary = aws.primary
    aws.dr      = aws.dr
  }

  project_name  = var.project_name
  environment   = var.environment
  account_id    = data.aws_caller_identity.current.account_id
  
  # Monitoring
  sns_topic_arn = module.monitoring_control_plane.sns_topic_arn
}

# -----------------------------------------------------------------------------
# ECR Cross-Region Replication
# Replicates container images from primary (us-east-1) to DR (us-west-2)
# -----------------------------------------------------------------------------

resource "aws_ecr_replication_configuration" "cross_region" {
  provider = aws.primary

  replication_configuration {
    rule {
      destination {
        region      = "us-west-2"
        registry_id = data.aws_caller_identity.current.account_id
      }

      repository_filter {
        filter      = "dr-platform"
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Compute - Primary Region (us-east-1)
# -----------------------------------------------------------------------------

module "compute_primary" {
  source = "./modules/compute"

  providers = {
    aws = aws.primary
  }

  region_name        = "primary"
  region_type        = "primary"
  project_name       = var.project_name
  environment        = var.environment
  
  # Network
  vpc_id             = module.networking_primary.vpc_id
  public_subnet_ids  = module.networking_primary.public_subnet_ids
  private_subnet_ids = module.networking_primary.private_subnet_ids
  alb_security_group_id = module.networking_primary.alb_security_group_id
  ecs_security_group_id = module.networking_primary.ecs_security_group_id
  
  # ECS Configuration
  frontend_cpu       = var.ecs_frontend_cpu
  frontend_memory    = var.ecs_frontend_memory
  backend_cpu        = var.ecs_backend_cpu
  backend_memory     = var.ecs_backend_memory
  min_tasks          = var.primary_min_tasks
  max_tasks          = var.primary_max_tasks
  
  # Database
  db_secret_arn      = module.database_primary.secret_arn
  
  # S3
  s3_bucket_name     = module.storage.primary_bucket_id

  depends_on = [module.networking_primary, module.database_primary, module.storage]
}

# -----------------------------------------------------------------------------
# Compute - DR Region (us-west-2)
# -----------------------------------------------------------------------------

module "compute_dr" {
  source = "./modules/compute"

  providers = {
    aws = aws.dr
  }

  region_name        = "dr"
  region_type        = "dr"
  project_name       = var.project_name
  environment        = var.environment
  
  # Network
  vpc_id             = module.networking_dr.vpc_id
  public_subnet_ids  = module.networking_dr.public_subnet_ids
  private_subnet_ids = module.networking_dr.private_subnet_ids
  alb_security_group_id = module.networking_dr.alb_security_group_id
  ecs_security_group_id = module.networking_dr.ecs_security_group_id
  
  # ECS Configuration
  frontend_cpu       = var.ecs_frontend_cpu
  frontend_memory    = var.ecs_frontend_memory
  backend_cpu        = var.ecs_backend_cpu
  backend_memory     = var.ecs_backend_memory
  min_tasks          = var.dr_min_tasks
  max_tasks          = var.dr_max_tasks
  
  # Database
  db_secret_arn      = module.database_dr.secret_arn
  
  # S3
  s3_bucket_name     = module.storage.dr_bucket_id

  depends_on = [module.networking_dr, module.database_dr, module.storage]
}

# -----------------------------------------------------------------------------
# Monitoring - SNS Topics for Alerts (Per Region)
# -----------------------------------------------------------------------------

# Control Plane SNS Topic
module "monitoring_control_plane" {
  source = "./modules/monitoring"

  providers = {
    aws = aws.control_plane
  }

  project_name = var.project_name
  environment  = var.environment
}

# Primary Region SNS Topic
module "monitoring_primary" {
  source = "./modules/monitoring"

  providers = {
    aws = aws.primary
  }

  project_name = var.project_name
  environment  = var.environment
}

# DR Region SNS Topic
module "monitoring_dr" {
  source = "./modules/monitoring"

  providers = {
    aws = aws.dr
  }

  project_name = var.project_name
  environment  = var.environment
}

# -----------------------------------------------------------------------------
# Control Plane - Step Functions, Lambda, DynamoDB
# -----------------------------------------------------------------------------

module "control_plane" {
  source = "./modules/control-plane"

  providers = {
    aws = aws.control_plane
  }

  project_name       = var.project_name
  environment        = var.environment
  domain_name        = var.domain_name
  
  # Primary region resources
  primary_region               = "us-east-1"
  primary_ecs_cluster_name     = module.compute_primary.ecs_cluster_name
  primary_ecs_frontend_service = module.compute_primary.frontend_service_name
  primary_ecs_backend_service  = module.compute_primary.backend_service_name
  primary_alb_arn              = module.compute_primary.alb_arn
  primary_alb_dns              = module.compute_primary.alb_dns_name
  primary_alb_zone_id          = "Z35SXDOTRQ7X7K"  # us-east-1 ALB hosted zone
  
  # DR region resources
  dr_region                = "us-west-2"
  dr_ecs_cluster_name      = module.compute_dr.ecs_cluster_name
  dr_ecs_frontend_service  = module.compute_dr.frontend_service_name
  dr_ecs_backend_service   = module.compute_dr.backend_service_name
  dr_alb_arn               = module.compute_dr.alb_arn
  dr_alb_dns               = module.compute_dr.alb_dns_name
  dr_alb_zone_id           = "Z1H1FL5HABSF5"  # us-west-2 ALB hosted zone
  
  # Database
  primary_db_identifier = module.database_primary.db_instance_id
  dr_db_identifier      = module.database_dr.db_instance_id
  
  # DR Configuration
  rto_target_minutes   = var.rto_target_minutes
  rpo_target_seconds   = var.rpo_target_seconds
  
  # Notifications
  notification_email   = var.notification_email

  depends_on = [module.compute_primary, module.compute_dr]
}

# Bastion Host for Database Initialization (REMOVED - no longer needed)
# Uncomment if you need to re-initialize the database

# module "bastion" {
#   source = "./modules/bastion"
#
#   providers = {
#     aws = aws.primary
#   }
#
#   project_name          = var.project_name
#   region_name           = "primary"
#   vpc_id                = module.networking_primary.vpc_id
#   public_subnet_id      = module.networking_primary.public_subnet_ids[0]
#   rds_security_group_id = module.networking_primary.rds_security_group_id
#   your_ip_cidr          = var.bastion_ip_cidr
# }
#
# output "bastion_ip" {
#   value = module.bastion.bastion_public_ip
# }
#
# output "bastion_logs" {
#   value = "ssh -i your-key.pem ec2-user@${module.bastion.bastion_public_ip} 'cat /var/log/db-init.log'"
# }
