# -----------------------------------------------------------------------------
# Networking Module - Main Configuration
# Creates VPC, Subnets, Security Groups, and VPC Endpoints
# -----------------------------------------------------------------------------

variable "region_name" {
  description = "Name identifier for this region (control-plane, primary, dr)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "enable_rds_security_group" {
  description = "Whether to create RDS security group"
  type        = bool
  default     = true
}

variable "allow_rds_replication" {
  description = "Whether to allow RDS replication from another VPC"
  type        = bool
  default     = false
}

variable "primary_vpc_cidr" {
  description = "CIDR of primary VPC for replication (used in DR region)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-${var.region_name}-vpc"
  }
}

# -----------------------------------------------------------------------------
# Internet Gateway
# -----------------------------------------------------------------------------

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.region_name}-igw"
  }
}

# -----------------------------------------------------------------------------
# Public Subnets (2 for ALB)
# -----------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.region_name}-public-${count.index + 1}"
    Type = "public"
  }
}

# -----------------------------------------------------------------------------
# Private Subnets (2 for ECS, RDS)
# -----------------------------------------------------------------------------

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 4)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-${var.region_name}-private-${count.index + 1}"
    Type = "private"
  }
}

# -----------------------------------------------------------------------------
# Route Tables
# -----------------------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.region_name}-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.region_name}-private-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# -----------------------------------------------------------------------------
# Security Group - ALB
# -----------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-${var.region_name}-alb-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for Application Load Balancer"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name = "${var.project_name}-${var.region_name}-alb-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Security Group - ECS Tasks
# -----------------------------------------------------------------------------

resource "aws_security_group" "ecs" {
  name_prefix = "${var.project_name}-${var.region_name}-ecs-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for ECS tasks"

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "From ALB"
  }

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Frontend from ALB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name = "${var.project_name}-${var.region_name}-ecs-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

variable "enable_db_bastion_access" {
  description = "Enable temporary bastion access to RDS"
  type        = bool
  default     = false
}

variable "bastion_ip_cidr" {
  description = "IP CIDR for bastion access"
  type        = string
  default     = "0.0.0.0/32"
}

# -----------------------------------------------------------------------------
# Security Group - RDS (Optional)
# -----------------------------------------------------------------------------

resource "aws_security_group" "rds" {
  count = var.enable_rds_security_group ? 1 : 0

  name_prefix = "${var.project_name}-${var.region_name}-rds-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for RDS database"

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
    description     = "PostgreSQL from ECS"
  }

  # Allow replication from primary region (DR only)
  dynamic "ingress" {
    for_each = var.allow_rds_replication && var.primary_vpc_cidr != "" ? [1] : []
    content {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [var.primary_vpc_cidr]
      description = "Replication from primary"
    }
  }

  # Temporary bastion access for database initialization
  dynamic "ingress" {
    for_each = var.enable_db_bastion_access ? [1] : []
    content {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [var.bastion_ip_cidr]
      description = "Temporary bastion access for DB init"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name = "${var.project_name}-${var.region_name}-rds-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Security Group - VPC Endpoints
# -----------------------------------------------------------------------------

resource "aws_security_group" "endpoints" {
  name_prefix = "${var.project_name}-${var.region_name}-endpoints-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for VPC Endpoints"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "HTTPS from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name = "${var.project_name}-${var.region_name}-endpoints-sg"
  }
}
