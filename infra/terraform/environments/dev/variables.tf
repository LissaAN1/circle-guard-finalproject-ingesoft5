# Defaults below are the sizing of the dev environment (desarrollo: un solo nodo k3s, logs 7 dias, recursos destruibles).
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
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets, one per availability zone."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
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
  default     = 0
}

variable "services" {
  description = "CircleGuard services that get an ECR repository and a log group."
  type        = list(string)
  default     = ["auth-service", "dashboard-service", "file-service", "form-service", "gateway-service", "identity-service", "notification-service", "promotion-service"]
}

variable "log_retention_days" {
  description = "Days CloudWatch keeps the service logs."
  type        = number
  default     = 7
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
