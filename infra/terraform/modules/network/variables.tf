variable "name" {
  description = "Prefix for every resource name, for example circleguard-dev."
  type        = string
}

variable "environment" {
  description = "Environment this network belongs to (dev, stage or prod)."
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage or prod."
  }
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
  description = "Availability zones for the subnets, one per entry of public_subnet_cidrs."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "Provide at least two availability zones."
  }

  validation {
    condition     = length(var.availability_zones) == length(var.public_subnet_cidrs)
    error_message = "The number of availability zones must match the number of public subnets."
  }
}

variable "admin_cidrs" {
  description = "CIDR blocks allowed to reach SSH and the Kubernetes API (operator IPs, never 0.0.0.0/0)."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "admin_cidrs must not open administration to the whole internet."
  }
}

variable "public_ingress_ports" {
  description = "TCP ports exposed to the internet on the cluster security group (web client and gateway)."
  type        = list(number)
  default     = [80, 443]

  validation {
    condition = alltrue([
      for p in var.public_ingress_ports :
      p >= 1 && p <= 65535 && !contains([22, 6443], p)
    ])
    error_message = "Public ingress ports must be valid TCP ports and cannot include SSH (22) or the Kubernetes API (6443)."
  }
}

variable "tags" {
  description = "Extra tags applied to every resource."
  type        = map(string)
  default     = {}
}
