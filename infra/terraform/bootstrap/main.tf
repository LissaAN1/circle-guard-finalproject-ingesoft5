# Remote state backend shared by the dev, stage and prod environments.
#
# This configuration is applied once, with local state, before any environment
# runs `terraform init` (an environment cannot store its state in a bucket that
# does not exist yet). Afterwards it rarely changes.

provider "aws" {
  region = var.region
}

locals {
  tags = merge(var.tags, {
    ManagedBy = "terraform"
    Purpose   = "terraform-state"
  })
}

# Versioned, private, TLS-only bucket (the storage module enforces all of it).
# Old state versions are kept for 90 days so a bad apply can be rolled back.
module "state_bucket" {
  source = "../modules/storage"

  name                               = var.name
  environment                        = "prod"
  purpose                            = "tfstate"
  versioning_enabled                 = true
  noncurrent_version_expiration_days = 90
  tags                               = local.tags
}

# Terraform takes a lock row here during plan/apply so two people (or two
# pipeline runs) cannot change the same environment at the same time.
resource "aws_dynamodb_table" "lock" {
  name         = "${var.name}-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  deletion_protection_enabled = var.lock_table_deletion_protection

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = local.tags
}
