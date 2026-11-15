# Plan-level tests with a mocked AWS provider: nothing is created in AWS.

mock_provider "aws" {}

variables {
  name        = "circleguard-test"
  environment = "dev"
  services    = ["auth-service", "gateway-service"]
}

run "defaults_are_secure" {
  command = plan

  assert {
    condition     = length(aws_ecr_repository.service) == 2
    error_message = "One repository per service expected."
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.service : r.image_tag_mutability == "IMMUTABLE"])
    error_message = "Tags must be immutable by default."
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.service : r.image_scanning_configuration[0].scan_on_push])
    error_message = "Scan on push must be enabled by default."
  }

  assert {
    condition     = aws_ecr_repository.service["auth-service"].name == "circleguard-test/auth-service"
    error_message = "Repository names must be prefixed with the module name."
  }
}

run "lifecycle_policy_per_repository" {
  command = plan

  assert {
    condition     = length(aws_ecr_lifecycle_policy.service) == 2
    error_message = "Each repository needs a lifecycle policy."
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

run "rejects_invalid_service_name" {
  command = plan

  variables {
    services = ["Auth Service"]
  }

  expect_failures = [var.services]
}

run "rejects_invalid_mutability" {
  command = plan

  variables {
    image_tag_mutability = "SOMETIMES"
  }

  expect_failures = [var.image_tag_mutability]
}

run "rejects_zero_image_retention" {
  command = plan

  variables {
    max_image_count = 0
  }

  expect_failures = [var.max_image_count]
}

run "rejects_unknown_environment" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}
