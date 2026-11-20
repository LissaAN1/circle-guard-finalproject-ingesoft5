output "budget_name" {
  description = "Name of the monthly budget of the environment."
  value       = aws_budgets_budget.environment.name
}

output "scale_to_zero_enabled" {
  description = "Whether the stop and start schedules exist."
  value       = local.schedule_enabled
}

output "schedule_names" {
  description = "Names of the stop and start schedules, empty when scale to zero is off."
  value       = concat(aws_scheduler_schedule.stop[*].name, aws_scheduler_schedule.start[*].name)
}
