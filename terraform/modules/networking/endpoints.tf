# -----------------------------------------------------------------------------
# VPC Endpoints - Replace NAT Gateway for cost savings
# Provides private access to AWS services from private subnets
# -----------------------------------------------------------------------------

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# S3 Gateway Endpoint (Free)
# -----------------------------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [aws_route_table.private.id]

  tags = {
    Name = "${var.project_name}-${var.region_name}-s3-endpoint"
  }
}

# -----------------------------------------------------------------------------
# Interface Endpoints (Cost: ~$7/month each)
# -----------------------------------------------------------------------------

# ECR API Endpoint
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.endpoints.id]

  tags = {
    Name = "${var.project_name}-${var.region_name}-ecr-api-endpoint"
  }
}

# ECR DKR Endpoint (for docker pull)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.endpoints.id]

  tags = {
    Name = "${var.project_name}-${var.region_name}-ecr-dkr-endpoint"
  }
}

# CloudWatch Logs Endpoint
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.endpoints.id]

  tags = {
    Name = "${var.project_name}-${var.region_name}-logs-endpoint"
  }
}

# Secrets Manager Endpoint
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.endpoints.id]

  tags = {
    Name = "${var.project_name}-${var.region_name}-secrets-endpoint"
  }
}

# SSM Endpoint (for reading parameters)
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.endpoints.id]

  tags = {
    Name = "${var.project_name}-${var.region_name}-ssm-endpoint"
  }
}
