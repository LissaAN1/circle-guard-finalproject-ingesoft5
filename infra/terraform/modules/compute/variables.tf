variable "name" {
  description = "Prefix for every resource name, for example circleguard-dev."
  type        = string
}

variable "environment" {
  description = "Environment this cluster belongs to (dev, stage or prod)."
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage or prod."
  }
}

variable "subnet_ids" {
  description = "Subnets where the nodes are placed (output public_subnet_ids of the network module)."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "Provide at least one subnet."
  }
}

variable "security_group_id" {
  description = "Security group attached to every node (output cluster_security_group_id of the network module)."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type of the k3s nodes."
  type        = string
  default     = "m7i-flex.large"
}

variable "root_volume_gb" {
  description = "Size in GB of the encrypted root volume of each node."
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_gb >= 20
    error_message = "root_volume_gb must be at least 20."
  }
}

variable "agent_count" {
  description = "Number of k3s agent (worker) nodes added to the single server node."
  type        = number
  default     = 0

  validation {
    condition     = var.agent_count >= 0 && var.agent_count <= 10
    error_message = "agent_count must be between 0 and 10."
  }
}

variable "k3s_version" {
  description = "k3s release installed on every node, for example v1.31.4+k3s1."
  type        = string
  default     = "v1.31.4+k3s1"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+\\+k3s[0-9]+$", var.k3s_version))
    error_message = "k3s_version must look like v1.31.4+k3s1."
  }
}

variable "ami_id" {
  description = "AMI for the nodes. When null the latest Ubuntu Server 24.04 LTS is resolved from the public SSM parameter."
  type        = string
  default     = null
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access. Null disables SSH key login."
  type        = string
  default     = null
}

variable "tags" {
  description = "Extra tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "registry_endpoint" {
  description = "Private image registry the nodes pull from, as host:port (for example the Nexus private address and port). Null leaves the nodes without a private registry."
  type        = string
  default     = null

  validation {
    condition     = var.registry_endpoint == null || can(regex("^[A-Za-z0-9.-]+:[0-9]{2,5}$", var.registry_endpoint))
    error_message = "registry_endpoint must look like host:port."
  }
}

variable "registry_username" {
  description = "Read-only account used to pull images from the private registry."
  type        = string
  default     = null
}

variable "registry_password_parameter" {
  description = "Name of an existing SSM SecureString (starting with /) that holds the registry password. It is created by the operator outside Terraform, so the password is never in the repository, the state or the user data."
  type        = string
  default     = null

  validation {
    condition = (
      var.registry_endpoint == null && var.registry_username == null && var.registry_password_parameter == null
      ) || (
      var.registry_endpoint != null && var.registry_username != null &&
      var.registry_password_parameter != null && try(startswith(var.registry_password_parameter, "/"), false)
    )
    error_message = "Set registry_endpoint, registry_username and registry_password_parameter (starting with /) together, or none of them."
  }
}
