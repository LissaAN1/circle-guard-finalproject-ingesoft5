output "vpc_id" {
  description = "VPC of the environment."
  value       = module.network.vpc_id
}

output "server_public_ip" {
  description = "Public IP of the k3s server (Kubernetes API and ingress entry point)."
  value       = module.compute.server_public_ip
}

output "server_instance_id" {
  description = "Instance id of the k3s server."
  value       = module.compute.server_instance_id
}

output "k3s_token_parameter_name" {
  description = "SSM parameter that holds the cluster join token."
  value       = module.compute.k3s_token_parameter_name
}

output "ecr_repository_urls" {
  description = "ECR repository URL of every service."
  value       = module.registry.repository_urls
}

output "artifacts_bucket" {
  description = "Bucket for artifacts and reports."
  value       = module.storage.bucket_name
}

output "log_group_names" {
  description = "CloudWatch log group of every service."
  value       = module.observability.log_group_names
}

output "alarm_topic_arn" {
  description = "SNS topic that receives the alarms."
  value       = module.observability.alarm_topic_arn
}
