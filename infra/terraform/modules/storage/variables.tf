variable "name" {
  description = "Prefix for the bucket name, for example circleguard-dev."
  type        = string
}

variable "environment" {
  description = "Environment this bucket belongs to (dev, stage or prod)."
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage or prod."
  }
}

variable "purpose" {
  description = "What the bucket stores; becomes part of its name (for example artifacts or reports)."
  type        = string
  default     = "artifacts"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.purpose))
    error_message = "purpose must be lowercase letters, digits and hyphens."
  }
}

variable "versioning_enabled" {
  description = "Keep previous versions of every object."
  type        = bool
  default     = true
}

variable "noncurrent_version_expiration_days" {
  description = "Days after which previous object versions are deleted."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1 && var.noncurrent_version_expiration_days == floor(var.noncurrent_version_expiration_days)
    error_message = "noncurrent_version_expiration_days must be a positive integer."
  }
}

variable "force_destroy" {
  description = "Allow destroying the bucket while it still contains objects. Only accepted in dev."
  type        = bool
  default     = false

  validation {
    condition     = !var.force_destroy || var.environment == "dev"
    error_message = "force_destroy may only be enabled in dev."
  }
}

variable "tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}
