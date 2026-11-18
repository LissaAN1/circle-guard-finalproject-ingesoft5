# Private peering between one application VPC and the CI/CD VPC. The Jenkins
# API access and Nexus image pulls remain on private addresses.
resource "aws_vpc_peering_connection" "this" {
  vpc_id      = var.environment_vpc_id
  peer_vpc_id = var.cicd_vpc_id
  auto_accept = true
  tags = {
    Name      = "${var.name}-cicd-peer"
    ManagedBy = "terraform"
  }
}

resource "aws_route" "environment_to_cicd" {
  route_table_id            = var.environment_route_table_id
  destination_cidr_block    = var.cicd_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}

# The CI/CD VPC may have separate route tables for Jenkins and Nexus.
resource "aws_route" "cicd_to_environment" {
  for_each                  = toset(var.cicd_route_table_ids)
  route_table_id            = each.value
  destination_cidr_block    = var.environment_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}

resource "aws_vpc_security_group_ingress_rule" "jenkins_k3s_api" {
  security_group_id = var.environment_security_group_id
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
  cidr_ipv4         = "${var.jenkins_private_ip}/32"
  description       = "Jenkins private Kubernetes API access"
}

resource "aws_vpc_security_group_ingress_rule" "nodes_nexus_pull" {
  security_group_id = var.nexus_security_group_id
  ip_protocol       = "tcp"
  from_port         = 8082
  to_port           = 8082
  cidr_ipv4         = var.environment_vpc_cidr
  description       = "K3s image pulls from ${var.name}"
}
