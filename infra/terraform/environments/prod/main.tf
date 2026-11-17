provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = local.environment
      ManagedBy   = "terraform"
    }
  }
}

locals {
  environment = "prod"
  name        = "${var.project}-${local.environment}"

  # Static labels (known at plan time) for the alarms of every node.
  monitored_instances = merge(
    { server = module.compute.server_instance_id },
    { for i in range(var.agent_count) : "agent${i + 1}" => module.compute.agent_instance_ids[i] },
  )
}

module "network" {
  source = "../../modules/network"

  name                = local.name
  environment         = local.environment
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  availability_zones  = var.availability_zones
  admin_cidrs         = var.admin_cidrs
}

module "compute" {
  source = "../../modules/compute"

  name              = local.name
  environment       = local.environment
  subnet_ids        = module.network.public_subnet_ids
  security_group_id = module.network.cluster_security_group_id
  instance_type     = var.instance_type
  root_volume_gb    = var.root_volume_gb
  agent_count       = var.agent_count
  key_name          = var.key_name
}

module "registry" {
  source = "../../modules/registry"

  name         = local.name
  environment  = local.environment
  services     = var.services
  force_delete = false
}

module "storage" {
  source = "../../modules/storage"

  name          = local.name
  environment   = local.environment
  purpose       = "artifacts"
  force_destroy = false
}

module "observability" {
  source = "../../modules/observability"

  name               = local.name
  environment        = local.environment
  services           = var.services
  log_retention_days = var.log_retention_days
  instances          = local.monitored_instances
  alarm_email        = var.alarm_email
}
