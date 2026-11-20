variable "name" {
  description = "Prefix for the budget, schedules and role, for example circleguard-dev."
  type        = string
}

variable "environment" {
  description = "Deployment environment: dev, stage or prod. Matches the Environment cost allocation tag."
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be one of: dev, stage, prod."
  }
}

variable "monthly_limit_usd" {
  description = "Monthly cost budget of the environment, in USD."
  type        = number

  validation {
    condition     = var.monthly_limit_usd > 0
    error_message = "monthly_limit_usd must be greater than zero."
  }
}

variable "alert_emails" {
  description = "E-mail addresses notified by the budget. Empty creates the budget without notifications."
  type        = list(string)
  default     = []
}

variable "instances" {
  description = "EC2 instances the schedule stops and starts: static label -> instance id. Labels must be known at plan time."
  type        = map(string)
  default     = {}
}

variable "scale_to_zero_enabled" {
  description = "Stop the instances outside working hours and start them again. Never enable it in prod."
  type        = bool
  default     = false

  validation {
    condition     = !(var.scale_to_zero_enabled && var.environment == "prod")
    error_message = "scale_to_zero_enabled must stay false in prod."
  }
}

variable "stop_schedule" {
  description = "EventBridge Scheduler cron expression that stops the instances."
  type        = string
  default     = "cron(0 20 * * ? *)"
}

variable "start_schedule" {
  description = "EventBridge Scheduler cron expression that starts the instances."
  type        = string
  default     = "cron(0 7 ? * MON-FRI *)"
}

variable "schedule_timezone" {
  description = "IANA time zone of both cron expressions."
  type        = string
  default     = "America/Bogota"
}

variable "tags" {
  description = "Extra tags for the resources that support them."
  type        = map(string)
  default     = {}
}
