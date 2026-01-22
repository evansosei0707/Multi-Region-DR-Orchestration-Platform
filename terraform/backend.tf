# Terraform State Backend Configuration
# State stored in control plane region (us-east-2) for independence

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "s3" {
    bucket         = "dr-platform-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-2"
    encrypt        = true
    dynamodb_table = "dr-platform-terraform-locks"
  }
}
