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

  registry_endpoint           = var.registry_endpoint
  registry_username           = var.registry_username
  registry_password_parameter = var.registry_password_parameter
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

# Optional for mock plans; mandatory in the Jenkins Kubernetes release tfvars.
module "cicd_link" {
  count  = var.cicd_vpc_id == null ? 0 : 1
  source = "../../modules/cicd_link"

  name                          = local.name
  environment_vpc_id            = module.network.vpc_id
  environment_vpc_cidr          = var.vpc_cidr
  environment_route_table_id    = module.network.public_route_table_id
  environment_security_group_id = module.network.cluster_security_group_id
  cicd_vpc_id                   = var.cicd_vpc_id
  cicd_vpc_cidr                 = var.cicd_vpc_cidr
  cicd_route_table_ids          = var.cicd_route_table_ids
  jenkins_private_ip            = var.jenkins_private_ip
  nexus_security_group_id       = var.nexus_security_group_id
}
