# Plan-level tests with a mocked AWS provider: nothing is created in AWS.

mock_provider "aws" {}

variables {
  name        = "circleguard-test"
  environment = "dev"
  services    = ["auth-service", "gateway-service"]
}

run "creates_a_log_group_per_service" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_group.service) == 2
    error_message = "One log group per service is expected."
  }

  assert {
    condition     = aws_cloudwatch_log_group.service["auth-service"].name == "/circleguard-test/auth-service"
    error_message = "Log group name must be /<name>/<service>."
  }

  assert {
    condition     = aws_cloudwatch_log_group.service["auth-service"].retention_in_days == 30
    error_message = "Default retention must be 30 days."
  }
}

run "no_alarms_or_subscription_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.cpu_high) == 0
    error_message = "No CPU alarms without instance ids."
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 0
    error_message = "No email subscription without alarm_email."
  }
}

run "creates_cpu_alarm_per_instance" {
  command = plan

  variables {
    instance_ids        = ["i-0abc123", "i-0def456"]
    cpu_alarm_threshold = 70
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.cpu_high) == 2
    error_message = "One alarm per instance is expected."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu_high["i-0abc123"].threshold == 70
    error_message = "The CPU threshold must be honored."
  }
}

run "subscribes_email_when_given" {
  command = plan

  variables {
    alarm_email = "ops@example.com"
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 1
    error_message = "An email subscription is expected."
  }
}

run "rejects_empty_services" {
  command = plan

  variables {
    services = []
  }

  expect_failures = [var.services]
}

run "rejects_duplicate_services" {
  command = plan

  variables {
    services = ["auth-service", "auth-service"]
  }

  expect_failures = [var.services]
}

run "rejects_invalid_retention" {
  command = plan

  variables {
    log_retention_days = 10
  }

  expect_failures = [var.log_retention_days]
}

run "rejects_out_of_range_threshold" {
  command = plan

  variables {
    cpu_alarm_threshold = 150
  }

  expect_failures = [var.cpu_alarm_threshold]
}

run "rejects_invalid_email" {
  command = plan

  variables {
    alarm_email = "not-an-email"
  }

  expect_failures = [var.alarm_email]
}

run "rejects_unknown_environment" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}
