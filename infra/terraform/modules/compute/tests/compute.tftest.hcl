# Plan-level tests with a mocked AWS provider: nothing is created in AWS.

mock_provider "aws" {}
mock_provider "random" {}

variables {
  name              = "circleguard-test"
  environment       = "dev"
  subnet_ids        = ["subnet-aaaa1111", "subnet-bbbb2222"]
  security_group_id = "sg-0123456789abcdef0"
}

run "defaults_create_a_single_server" {
  command = plan

  assert {
    condition     = length(aws_instance.agent) == 0
    error_message = "No agents expected by default."
  }

  assert {
    condition     = aws_instance.server.root_block_device[0].encrypted == true
    error_message = "The root volume must be encrypted."
  }

  assert {
    condition     = aws_instance.server.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required."
  }
}

run "agents_are_created_on_demand" {
  command = plan

  variables {
    agent_count = 2
  }

  assert {
    condition     = length(aws_instance.agent) == 2
    error_message = "Expected two agents."
  }
}

run "rejects_negative_agent_count" {
  command = plan

  variables {
    agent_count = -1
  }

  expect_failures = [var.agent_count]
}

run "rejects_too_many_agents" {
  command = plan

  variables {
    agent_count = 11
  }

  expect_failures = [var.agent_count]
}

run "rejects_empty_subnets" {
  command = plan

  variables {
    subnet_ids = []
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_small_root_volume" {
  command = plan

  variables {
    root_volume_gb = 10
  }

  expect_failures = [var.root_volume_gb]
}

run "rejects_malformed_k3s_version" {
  command = plan

  variables {
    k3s_version = "1.31"
  }

  expect_failures = [var.k3s_version]
}

run "rejects_unknown_environment" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}
