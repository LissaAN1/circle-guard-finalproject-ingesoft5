variable "region" {
  description = "AWS region where the state bucket and the lock table live."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Prefix of the state bucket and the lock table."
  type        = string
  default     = "circleguard"
}

variable "lock_table_deletion_protection" {
  description = "Protect the lock table from accidental deletion."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}
