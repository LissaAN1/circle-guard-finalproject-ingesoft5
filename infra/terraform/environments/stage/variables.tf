# Defaults below are the sizing of the stage environment (pre-produccion: servidor y un agente, logs 30 dias).
# Account-specific values (operator IPs, key pair, alert email) are not here:
# copy terraform.tfvars.example to terraform.tfvars, which git ignores.

variable "region" {
  description = "AWS region of the environment."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project prefix of every resource name."
  type        = string
  default     = "circleguard"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.1.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets, one per availability zone."
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "availability_zones" {
  description = "Availability zones of the subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "instance_type" {
  description = "EC2 instance type of the k3s nodes."
  type        = string
  default     = "m7i-flex.large"
}

variable "root_volume_gb" {
  description = "Size in GB of the root volume of each node."
  type        = number
  default     = 30
}

variable "agent_count" {
  description = "Number of k3s agent nodes added to the server."
  type        = number
  default     = 1
}

variable "services" {
  description = "CircleGuard services that get an ECR repository and a log group."
  type        = list(string)
  default     = ["auth-service", "dashboard-service", "file-service", "form-service", "gateway-service", "identity-service", "notification-service", "promotion-service"]
}

variable "log_retention_days" {
  description = "Days CloudWatch keeps the service logs."
  type        = number
  default     = 30
}

variable "admin_cidrs" {
  description = "Operator CIDR blocks allowed to reach SSH and the Kubernetes API. Never 0.0.0.0/0."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "admin_cidrs must not open administration to the whole internet."
  }
}

variable "key_name" {
  description = "Existing EC2 key pair for SSH. Null disables SSH key login."
  type        = string
  default     = null
}

variable "alarm_email" {
  description = "Email subscribed to the alarm topic. Empty means no subscription."
  type        = string
  default     = ""
}

variable "cicd_vpc_id" {
  description = "Existing CI/CD VPC; null disables the private link for offline tests."
  type        = string
  default     = null
  validation {
    condition = (
      var.cicd_vpc_id == null && var.cicd_vpc_cidr == null &&
      length(var.cicd_route_table_ids) == 0 && var.jenkins_private_ip == null &&
      var.nexus_security_group_id == null
      ) || (
      var.cicd_vpc_id != null && var.cicd_vpc_cidr != null &&
      length(var.cicd_route_table_ids) > 0 && var.jenkins_private_ip != null &&
      var.nexus_security_group_id != null
    )
    error_message = "Provide all CI/CD peering variables together, or none for mock tests."
  }
}
variable "cicd_vpc_cidr" {
  type    = string
  default = null
}
variable "cicd_route_table_ids" {
  type    = list(string)
  default = []
}
variable "jenkins_private_ip" {
  type    = string
  default = null
}
variable "nexus_security_group_id" {
  type    = string
  default = null
}

variable "registry_endpoint" {
  description = "Private image registry (Nexus) the k3s nodes pull from, host:port. Null: no private registry."
  type        = string
  default     = null
}

variable "registry_username" {
  description = "Read-only account of the private registry."
  type        = string
  default     = null
}

variable "registry_password_parameter" {
  description = "Name of the SSM SecureString (starting with /) that holds the registry password; created by the operator, never by Terraform."
  type        = string
  default     = null
}

variable "monthly_limit_usd" {
  description = "Monthly cost budget of the stage environment, in USD."
  type        = number
  default     = 40
}

variable "scale_to_zero_enabled" {
  description = "Stop the nodes outside working hours (FinOps). Set false while the environment is in use at night."
  type        = bool
  default     = true
}

variable "stop_schedule" {
  description = "Cron expression (America/Bogota) that stops the nodes."
  type        = string
  default     = "cron(0 20 * * ? *)"
}

variable "start_schedule" {
  description = "Cron expression (America/Bogota) that starts the nodes on working days."
  type        = string
  default     = "cron(0 7 ? * MON-FRI *)"
}
