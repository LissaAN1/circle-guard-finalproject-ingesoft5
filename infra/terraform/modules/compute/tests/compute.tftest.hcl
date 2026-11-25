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

run "registry_is_off_by_default" {
  command = plan

  assert {
    condition     = !strcontains(aws_instance.server.user_data, "registries.yaml")
    error_message = "Without a registry the nodes must not write registries.yaml."
  }
}

# apply against the mocked provider (nothing is created): the agent user data needs the
# server private IP, which is unknown at plan time.
run "registry_is_written_on_server_and_agents" {
  command = apply

  variables {
    agent_count                 = 1
    registry_endpoint           = "172.31.5.84:8082"
    registry_username           = "cg-reader"
    registry_password_parameter = "/circleguard/nexus/cg-reader"
  }

  assert {
    condition = alltrue([
      strcontains(aws_instance.server.user_data, "http://172.31.5.84:8082"),
      strcontains(aws_instance.agent[0].user_data, "http://172.31.5.84:8082"),
      strcontains(aws_instance.server.user_data, "/etc/rancher/k3s/registries.yaml"),
      strcontains(aws_instance.agent[0].user_data, "umask 077"),
    ])
    error_message = "Server and agents must write registries.yaml for the private registry."
  }

  assert {
    condition     = !strcontains(aws_instance.server.user_data, "VALOR") && strcontains(aws_instance.server.user_data, "/circleguard/nexus/cg-reader")
    error_message = "The user data may only reference the SSM parameter name, never a password value."
  }
}

run "rejects_a_partial_registry_configuration" {
  command = plan

  variables {
    registry_endpoint = "172.31.5.84:8082"
  }

  expect_failures = [var.registry_password_parameter]
}

run "rejects_a_malformed_registry_endpoint" {
  command = plan

  variables {
    registry_endpoint           = "http://nexus"
    registry_username           = "cg-reader"
    registry_password_parameter = "/circleguard/nexus/cg-reader"
  }

  expect_failures = [var.registry_endpoint]
}
