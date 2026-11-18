output "vpc_peering_connection_id" {
  description = "ID of the private link between the application and CI/CD VPCs."
  value       = aws_vpc_peering_connection.this.id
}
