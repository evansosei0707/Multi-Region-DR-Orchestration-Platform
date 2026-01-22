# Multi-Region Provider Configuration
# Control Plane: us-east-2 | Primary: us-east-1 | DR: us-west-2

# Default provider (Control Plane)
provider "aws" {
  region = "us-east-2"

  default_tags {
    tags = {
      Project     = "DR-Orchestration-Platform"
      ManagedBy   = "Terraform"
      Environment = "production"
    }
  }
}

# Control Plane Provider (explicit alias)
provider "aws" {
  alias  = "control_plane"
  region = "us-east-2"

  default_tags {
    tags = {
      Project     = "DR-Orchestration-Platform"
      ManagedBy   = "Terraform"
      Environment = "production"
      Role        = "control-plane"
    }
  }
}

# Primary Region Provider
provider "aws" {
  alias  = "primary"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "DR-Orchestration-Platform"
      ManagedBy   = "Terraform"
      Environment = "production"
      Role        = "primary"
    }
  }
}

# DR Region Provider
provider "aws" {
  alias  = "dr"
  region = "us-west-2"

  default_tags {
    tags = {
      Project     = "DR-Orchestration-Platform"
      ManagedBy   = "Terraform"
      Environment = "production"
      Role        = "disaster-recovery"
    }
  }
}
