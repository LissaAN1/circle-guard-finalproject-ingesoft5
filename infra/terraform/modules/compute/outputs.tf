output "server_instance_id" {
  description = "ID of the k3s server instance."
  value       = aws_instance.server.id
}

output "server_private_ip" {
  description = "Private IP of the k3s server (used by agents and in-cluster traffic)."
  value       = aws_instance.server.private_ip
}

output "server_public_ip" {
  description = "Public IP of the k3s server (Kubernetes API and ingress entry point)."
  value       = aws_instance.server.public_ip
}

output "agent_instance_ids" {
  description = "IDs of the k3s agent instances."
  value       = aws_instance.agent[*].id
}

output "k3s_token_parameter_name" {
  description = "Name of the SSM parameter that holds the cluster join token (the value is never output)."
  value       = aws_ssm_parameter.k3s_token.name
}
