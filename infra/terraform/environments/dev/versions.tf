terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Partial configuration: bucket, table and region come from backend.hcl
  # (see backend.hcl.example), so no account data lives in the repository.
  backend "s3" {}
}
