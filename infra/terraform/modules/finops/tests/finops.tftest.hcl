# Plan-level tests with a mocked AWS provider: nothing is created in AWS.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

variables {
  name              = "circleguard-test"
  environment       = "dev"
  monthly_limit_usd = 40
}

run "budget_follows_the_environment_tag_and_excludes_credits" {
  command = plan

  assert {
    condition     = aws_budgets_budget.environment.name == "circleguard-test-monthly"
    error_message = "Budget name must be <name>-monthly."
  }

  assert {
    condition     = contains(one(aws_budgets_budget.environment.cost_filter).values, "user:Environment$dev")
    error_message = "The budget must filter by the Environment cost allocation tag."
  }

  assert {
    condition     = one(aws_budgets_budget.environment.cost_types).include_credit == false
    error_message = "Credits must be excluded or the alerts never fire."
  }

  assert {
    condition     = aws_budgets_budget.environment.limit_amount == "40"
    error_message = "The limit must come from monthly_limit_usd."
  }
}

run "no_notifications_without_emails" {
  command = plan

  assert {
    condition     = length(aws_budgets_budget.environment.notification) == 0
    error_message = "No notification is expected without alert_emails."
  }
}

run "alerts_at_50_80_100_and_forecast" {
  command = plan

  variables {
    alert_emails = ["ops@example.com"]
  }

  assert {
    condition     = length(aws_budgets_budget.environment.notification) == 4
    error_message = "Three actual thresholds plus one forecast are expected."
  }
}

run "no_schedule_by_default" {
  command = plan

  variables {
    instances = { server = "i-0123456789abcdef0" }
  }

  assert {
    condition     = length(aws_scheduler_schedule.stop) == 0 && length(aws_scheduler_schedule.start) == 0
    error_message = "Scale to zero is opt in."
  }
}

run "schedules_stop_and_start_the_nodes" {
  command = plan

  variables {
    scale_to_zero_enabled = true
    instances = {
      server = "i-0123456789abcdef0"
      agent1 = "i-0fedcba9876543210"
    }
  }

  assert {
    condition     = length(aws_scheduler_schedule.stop) == 1 && length(aws_scheduler_schedule.start) == 1
    error_message = "One stop and one start schedule are expected."
  }

  assert {
    condition     = aws_scheduler_schedule.stop[0].schedule_expression == "cron(0 20 * * ? *)"
    error_message = "Default stop time is 20:00 every day."
  }

  assert {
    condition     = aws_scheduler_schedule.start[0].schedule_expression == "cron(0 7 ? * MON-FRI *)"
    error_message = "Default start time is 07:00 on working days."
  }

  assert {
    condition     = aws_scheduler_schedule.stop[0].schedule_expression_timezone == "America/Bogota"
    error_message = "Schedules use the Bogota time zone."
  }
}

run "schedule_needs_instances" {
  command = plan

  variables {
    scale_to_zero_enabled = true
  }

  assert {
    condition     = length(aws_scheduler_schedule.stop) == 0
    error_message = "Without instances there is nothing to schedule."
  }
}

run "prod_cannot_scale_to_zero" {
  command = plan

  variables {
    environment           = "prod"
    scale_to_zero_enabled = true
    instances             = { server = "i-0123456789abcdef0" }
  }

  expect_failures = [var.scale_to_zero_enabled]
}
