output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, in the same order as the input CIDRs."
  value       = aws_subnet.public[*].id
}

output "cluster_security_group_id" {
  description = "ID of the security group to attach to the cluster nodes."
  value       = aws_security_group.cluster.id
}
