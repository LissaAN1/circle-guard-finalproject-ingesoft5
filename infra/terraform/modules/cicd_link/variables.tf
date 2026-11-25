variable "name" { type = string }
variable "environment_vpc_id" { type = string }
variable "environment_vpc_cidr" { type = string }
variable "environment_route_table_id" { type = string }
variable "environment_security_group_id" { type = string }
variable "cicd_vpc_id" { type = string }
variable "cicd_vpc_cidr" { type = string }
variable "cicd_route_table_ids" {
  type = list(string)
  validation {
    condition     = length(var.cicd_route_table_ids) >= 1
    error_message = "At least one CI/CD route table is required."
  }
}
variable "jenkins_private_ip" {
  type = string
  validation {
    condition     = can(cidrhost("${var.jenkins_private_ip}/32", 0))
    error_message = "jenkins_private_ip must be an IPv4 address."
  }
}
variable "nexus_security_group_id" { type = string }
