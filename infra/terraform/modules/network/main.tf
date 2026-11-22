locals {
  tags = merge(
    {
      Project     = "circleguard"
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags,
  )
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${var.name}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-igw" })
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, { Name = "${var.name}-public-${count.index + 1}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.tags, { Name = "${var.name}-public-rt" })

  # Other modules (cicd_link) add their own aws_route entries to this table,
  # such as the VPC peering route to Jenkins and Nexus. Without this, every
  # plan would try to delete those routes to match the inline block above.
  lifecycle {
    ignore_changes = [route]
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security group shared by the cluster nodes of one environment.
resource "aws_security_group" "cluster" {
  name        = "${var.name}-cluster"
  description = "CircleGuard ${var.environment} cluster nodes"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-cluster" })
}

resource "aws_vpc_security_group_ingress_rule" "public" {
  for_each = toset([for p in var.public_ingress_ports : tostring(p)])

  security_group_id = aws_security_group.cluster.id
  description       = "Public web traffic on port ${each.value}"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  cidr_ipv4         = "0.0.0.0/0"
}

# SSH (22) and the Kubernetes API (6443) only from the operator addresses.
resource "aws_vpc_security_group_ingress_rule" "admin" {
  for_each = {
    for pair in setproduct(var.admin_cidrs, [22, 6443]) :
    "${pair[0]}-${pair[1]}" => { cidr = pair[0], port = pair[1] }
  }

  security_group_id = aws_security_group.cluster.id
  description       = "Admin access on port ${each.value.port}"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
}

# Nodes talk to each other freely (pod traffic, kubelet, etcd).
resource "aws_vpc_security_group_ingress_rule" "intra_cluster" {
  security_group_id            = aws_security_group.cluster.id
  description                  = "Traffic between cluster nodes"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.cluster.id
}

# Private communication between nodes of the same K3s cluster.
resource "aws_vpc_security_group_egress_rule" "intra_cluster" {
  security_group_id            = aws_security_group.cluster.id
  description                  = "Private traffic between K3s nodes"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.cluster.id
}

# Private access to the Nexus Docker registry through VPC peering.
resource "aws_vpc_security_group_egress_rule" "nexus" {
  count = var.cicd_vpc_cidr == null ? 0 : 1

  security_group_id = aws_security_group.cluster.id
  description       = "Private Nexus Docker registry access"
  ip_protocol       = "tcp"
  from_port         = 8082
  to_port           = 8082
  cidr_ipv4         = var.cicd_vpc_cidr
}

# Temporary lab exception: K3s requires outbound access for installation,
# image pulls and external dependencies. Restrict before production use.
# trivy:ignore:AWS-0104
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.cluster.id
  description       = "Outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
