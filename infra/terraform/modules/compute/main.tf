data "aws_region" "current" {}

data "aws_ssm_parameter" "ubuntu_ami" {
  count = var.ami_id == null ? 1 : 0

  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

locals {
  ami_id = var.ami_id != null ? var.ami_id : data.aws_ssm_parameter.ubuntu_ami[0].value

  tags = merge(
    {
      Project     = "circleguard"
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags,
  )

  token_parameter = "/${var.name}/k3s/token"
}

# The cluster join token is generated here and kept in SSM Parameter Store
# (SecureString). Nodes read it at boot; it never appears in the repository.
resource "random_password" "k3s_token" {
  length  = 48
  special = false
}

resource "aws_ssm_parameter" "k3s_token" {
  name        = local.token_parameter
  description = "k3s join token of ${var.name}"
  type        = "SecureString"
  value       = random_password.k3s_token.result

  tags = local.tags
}

resource "aws_iam_role" "node" {
  name = "${var.name}-k3s-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "read_token" {
  name = "read-k3s-token"
  role = aws_iam_role.node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = aws_ssm_parameter.k3s_token.arn
      },
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      },
    ]
  })
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.name}-k3s-node"
  role = aws_iam_role.node.name

  tags = local.tags
}

resource "aws_instance" "server" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_ids[0]
  vpc_security_group_ids = [var.security_group_id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.node.name

  user_data = templatefile("${path.module}/templates/server.sh.tftpl", {
    region          = data.aws_region.current.name
    token_parameter = local.token_parameter
    k3s_version     = var.k3s_version
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_gb
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(local.tags, { Name = "${var.name}-server", Role = "k3s-server" })
}

resource "aws_instance" "agent" {
  count = var.agent_count

  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids = [var.security_group_id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.node.name

  user_data = templatefile("${path.module}/templates/agent.sh.tftpl", {
    region          = data.aws_region.current.name
    token_parameter = local.token_parameter
    k3s_version     = var.k3s_version
    server_ip       = aws_instance.server.private_ip
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_gb
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(local.tags, { Name = "${var.name}-agent-${count.index + 1}", Role = "k3s-agent" })
}
