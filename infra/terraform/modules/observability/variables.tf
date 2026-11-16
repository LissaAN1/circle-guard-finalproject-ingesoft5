variable "name" {
  description = "Prefix for the log groups and alarms, for example circleguard-dev."
  type        = string
}

variable "environment" {
  description = "Deployment environment: dev, stage or prod."
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be one of: dev, stage, prod."
  }
}

variable "services" {
  description = "Services that get their own CloudWatch log group."
  type        = list(string)

  validation {
    condition     = length(var.services) >= 1
    error_message = "services must contain at least one name."
  }

  validation {
    condition     = length(var.services) == length(distinct(var.services))
    error_message = "services must not contain duplicates."
  }

  validation {
    condition     = alltrue([for s in var.services : can(regex("^[a-z0-9]+([-_][a-z0-9]+)*$", s))])
    error_message = "Each service name must use lowercase letters, digits, hyphens or underscores."
  }
}

variable "log_retention_days" {
  description = "Days to keep logs. Must be a retention value CloudWatch accepts."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts (for example 7, 14, 30, 90, 365)."
  }
}

variable "instances" {
  description = "EC2 instances that get a high-CPU alarm, as a map of a static label to the instance id. The labels must be known at plan time; the ids may be computed (for example module.compute.server_instance_id)."
  type        = map(string)
  default     = {}
}

variable "cpu_alarm_threshold" {
  description = "Average CPU percentage that triggers the alarm."
  type        = number
  default     = 80

  validation {
    condition     = var.cpu_alarm_threshold >= 1 && var.cpu_alarm_threshold <= 100
    error_message = "cpu_alarm_threshold must be between 1 and 100."
  }
}

variable "kms_key_arn" {
  description = "Optional customer-managed KMS key ARN used to encrypt the SNS topic and the log groups. Its policy must allow cloudwatch.amazonaws.com and the logs service to use it. Null keeps the default (no KMS)."
  type        = string
  default     = null
}

variable "alarm_email" {
  description = "Optional email subscribed to the alarm topic. Empty means no subscription."
  type        = string
  default     = ""

  validation {
    condition     = var.alarm_email == "" || can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", var.alarm_email))
    error_message = "alarm_email must be empty or a valid email address."
  }
}

variable "tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}
