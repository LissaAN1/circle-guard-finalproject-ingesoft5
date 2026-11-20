data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "finops"
  })

  schedule_enabled = var.scale_to_zero_enabled && length(var.instances) > 0
  instance_ids     = values(var.instances)
  instance_arns    = [for id in local.instance_ids : "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/${id}"]
}

# Monthly budget of one environment. It follows the Environment cost allocation tag,
# which must be active in Billing. Credits and refunds are left out on purpose: with
# them the net spend stays at zero while credits last and no alert would ever fire.
resource "aws_budgets_budget" "environment" {
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:Environment$%s", var.environment)]
  }

  cost_types {
    include_credit = false
    include_refund = false
  }

  dynamic "notification" {
    for_each = length(var.alert_emails) == 0 ? [] : [50, 80, 100]

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = var.alert_emails
    }
  }

  dynamic "notification" {
    for_each = length(var.alert_emails) == 0 ? [] : [100]

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "FORECASTED"
      subscriber_email_addresses = var.alert_emails
    }
  }
}

# Scale to zero of a non-production environment: the nodes are stopped outside working
# hours (compute billing stops, volumes stay) and started again on working days.
data "aws_iam_policy_document" "scheduler_trust" {
  count = local.schedule_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_iam_policy_document" "scheduler_ec2" {
  count = local.schedule_enabled ? 1 : 0

  statement {
    actions   = ["ec2:StartInstances", "ec2:StopInstances"]
    resources = local.instance_arns
  }
}

resource "aws_iam_role" "scheduler" {
  count = local.schedule_enabled ? 1 : 0

  name               = "${var.name}-scale-to-zero"
  assume_role_policy = data.aws_iam_policy_document.scheduler_trust[0].json

  tags = local.tags
}

resource "aws_iam_role_policy" "scheduler" {
  count = local.schedule_enabled ? 1 : 0

  name   = "start-stop-nodes"
  role   = aws_iam_role.scheduler[0].id
  policy = data.aws_iam_policy_document.scheduler_ec2[0].json
}

resource "aws_scheduler_schedule" "stop" {
  count = local.schedule_enabled ? 1 : 0

  name                         = "${var.name}-stop-nodes"
  description                  = "Stops the ${var.environment} nodes outside working hours."
  schedule_expression          = var.stop_schedule
  schedule_expression_timezone = var.schedule_timezone
  state                        = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.scheduler[0].arn
    input    = jsonencode({ InstanceIds = local.instance_ids })
  }
}

resource "aws_scheduler_schedule" "start" {
  count = local.schedule_enabled ? 1 : 0

  name                         = "${var.name}-start-nodes"
  description                  = "Starts the ${var.environment} nodes on working days."
  schedule_expression          = var.start_schedule
  schedule_expression_timezone = var.schedule_timezone
  state                        = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:startInstances"
    role_arn = aws_iam_role.scheduler[0].arn
    input    = jsonencode({ InstanceIds = local.instance_ids })
  }
}
