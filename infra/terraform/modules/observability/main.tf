locals {
  tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "observability"
  })
}

# One log group per service, with a bounded retention so logs do not grow forever.
resource "aws_cloudwatch_log_group" "service" {
  for_each = toset(var.services)

  name              = "/${var.name}/${each.value}"
  retention_in_days = var.log_retention_days

  tags = local.tags
}

# Alarm notifications go to a single SNS topic.
resource "aws_sns_topic" "alarms" {
  name = "${var.name}-alarms"

  tags = local.tags
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alarm_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = toset(var.instance_ids)

  alarm_name          = "${var.name}-cpu-high-${each.value}"
  alarm_description   = "Average CPU above ${var.cpu_alarm_threshold}% for 10 minutes."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.cpu_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = each.value
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = local.tags
}
