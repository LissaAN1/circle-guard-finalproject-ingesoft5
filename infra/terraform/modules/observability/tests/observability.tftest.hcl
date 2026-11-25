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
    instances = {
      server = "i-0abc123"
      agent1 = "i-0def456"
    }
    cpu_alarm_threshold = 70
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.cpu_high) == 2
    error_message = "One alarm per instance is expected."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu_high["server"].threshold == 70
    error_message = "The CPU threshold must be honored."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu_high["server"].alarm_name == "circleguard-test-cpu-high-server"
    error_message = "The alarm name must use the instance label."
  }
}

# Regression: instance ids that are only known after apply must not break the plan.
run "accepts_instance_ids_computed_at_apply" {
  command = plan

  module {
    source = "./tests/with_computed_instance"
  }

  assert {
    condition     = output.alarm_count == 1
    error_message = "An alarm is expected for an instance whose id is computed at apply."
  }
}

run "encrypts_with_kms_when_given" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = aws_sns_topic.alarms.kms_master_key_id == var.kms_key_arn
    error_message = "The SNS topic must use the given KMS key."
  }

  assert {
    condition     = aws_cloudwatch_log_group.service["auth-service"].kms_key_id == var.kms_key_arn
    error_message = "The log groups must use the given KMS key."
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

run "rejects_fractional_threshold_below_one" {
  command = plan

  variables {
    cpu_alarm_threshold = 0.5
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
