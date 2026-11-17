# Plan-level tests with mocked providers: nothing is created in AWS.

mock_provider "aws" {
  mock_data "aws_ssm_parameter" {
    defaults = {
      value = "ami-0123456789abcdef0"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "random" {}

variables {
  admin_cidrs = ["203.0.113.10/32"]
}

run "wires_every_module_for_dev" {
  command = plan

  assert {
    condition     = local.name == "circleguard-dev"
    error_message = "Resources must be named circleguard-dev."
  }

  assert {
    condition     = length(module.registry.repository_arns) == length(var.services)
    error_message = "Every service needs an ECR repository."
  }

  assert {
    condition     = length(module.observability.log_group_names) == length(var.services)
    error_message = "Every service needs a log group."
  }
}

run "monitors_server_and_every_agent" {
  command = plan

  assert {
    condition     = length(local.monitored_instances) == var.agent_count + 1
    error_message = "One alarm per node (server plus agents) is expected."
  }
}

run "uses_the_dev_sizing" {
  command = plan

  assert {
    condition     = var.agent_count == 0 && var.log_retention_days == 7
    error_message = "dev must keep its own agent count and log retention."
  }
}

run "rejects_open_administration" {
  command = plan

  variables {
    admin_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.admin_cidrs]
}
