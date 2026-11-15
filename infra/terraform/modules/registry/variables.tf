variable "name" {
  description = "Prefix for every repository name, for example circleguard-dev."
  type        = string
}

variable "environment" {
  description = "Environment these repositories belong to (dev, stage or prod)."
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage or prod."
  }
}

variable "services" {
  description = "Service names that get their own image repository (one repository per service)."
  type        = list(string)

  validation {
    condition     = length(var.services) >= 1
    error_message = "Provide at least one service."
  }

  validation {
    condition     = length(distinct(var.services)) == length(var.services)
    error_message = "Service names must be unique."
  }

  validation {
    condition     = alltrue([for s in var.services : can(regex("^[a-z0-9]+([-_][a-z0-9]+)*$", s))])
    error_message = "Service names must be lowercase letters, digits, hyphens or underscores."
  }
}

variable "image_tag_mutability" {
  description = "MUTABLE or IMMUTABLE. IMMUTABLE prevents overwriting a published tag."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Scan every pushed image for known vulnerabilities."
  type        = bool
  default     = true
}

variable "max_image_count" {
  description = "Number of most recent images kept per repository; older ones expire."
  type        = number
  default     = 20

  validation {
    condition     = var.max_image_count >= 1 && var.max_image_count == floor(var.max_image_count)
    error_message = "max_image_count must be a positive integer."
  }
}

variable "force_delete" {
  description = "Allow destroying repositories that still contain images (use true only in dev)."
  type        = bool
  default     = false

  validation {
    condition     = !var.force_delete || var.environment == "dev"
    error_message = "force_delete may only be enabled in dev."
  }
}

variable "tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}
