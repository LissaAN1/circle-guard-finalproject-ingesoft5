# Plan-level tests with a mocked AWS provider: nothing is created in AWS.

mock_provider "aws" {}

variables {
  name        = "circleguard-test"
  environment = "dev"
}

run "defaults_are_valid" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "Expected two public subnets by default."
  }
}

run "rejects_ssh_as_public_port" {
  command = plan

  variables {
    public_ingress_ports = [80, 22]
  }

  expect_failures = [var.public_ingress_ports]
}

run "rejects_kubernetes_api_as_public_port" {
  command = plan

  variables {
    public_ingress_ports = [6443]
  }

  expect_failures = [var.public_ingress_ports]
}

run "rejects_open_admin_cidr" {
  command = plan

  variables {
    admin_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.admin_cidrs]
}

run "rejects_mismatched_zones_and_subnets" {
  command = plan

  variables {
    public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  }

  expect_failures = [var.availability_zones]
}

run "rejects_single_zone" {
  command = plan

  variables {
    public_subnet_cidrs = ["10.0.1.0/24"]
    availability_zones  = ["us-east-1a"]
  }

  expect_failures = [var.availability_zones]
}
