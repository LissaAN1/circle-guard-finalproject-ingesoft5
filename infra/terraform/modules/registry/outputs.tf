output "repository_urls" {
  description = "Map of service name to its ECR repository URL."
  value       = { for s, r in aws_ecr_repository.service : s => r.repository_url }
}

output "repository_arns" {
  description = "Map of service name to its ECR repository ARN."
  value       = { for s, r in aws_ecr_repository.service : s => r.arn }
}
