# -----------------------------------------------------------------------------
# Compute Module - ECR Repositories
# -----------------------------------------------------------------------------

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# ECR Repository - Frontend
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "frontend" {
  name = "${var.project_name}-frontend"

  image_scanning_configuration {
    scan_on_push = true
  }

  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name   = "${var.project_name}-frontend-${var.region_name}"
    Region = var.region_name
  }
}

# -----------------------------------------------------------------------------
# ECR Repository - Backend
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "backend" {
  name = "${var.project_name}-backend"

  image_scanning_configuration {
    scan_on_push = true
  }

  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name   = "${var.project_name}-backend-${var.region_name}"
    Region = var.region_name
  }
}

# -----------------------------------------------------------------------------
# ECR Lifecycle Policy - Keep last 3 images
# -----------------------------------------------------------------------------

resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 3 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 3
      }
      action = {
        type = "expire"
      }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 3 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 3
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# -----------------------------------------------------------------------------
# ECR Replication Configuration (Primary region only)
# -----------------------------------------------------------------------------

resource "aws_ecr_replication_configuration" "main" {
  count = var.region_type == "primary" ? 1 : 0

  replication_configuration {
    rule {
      destination {
        region      = "us-west-2"  # DR region
        registry_id = data.aws_caller_identity.current.account_id
      }

      repository_filter {
        filter      = "${var.project_name}-*"
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}
