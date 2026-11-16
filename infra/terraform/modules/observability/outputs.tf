output "log_group_names" {
  description = "Map of service name to CloudWatch log group name."
  value       = { for k, g in aws_cloudwatch_log_group.service : k => g.name }
}

output "alarm_topic_arn" {
  description = "ARN of the SNS topic that receives alarm notifications."
  value       = aws_sns_topic.alarms.arn
}

output "cpu_alarm_names" {
  description = "Names of the high-CPU alarms, one per instance."
  value       = [for a in aws_cloudwatch_metric_alarm.cpu_high : a.alarm_name]
}
