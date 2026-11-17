# Plan-level tests with a mocked AWS provider: nothing is created in AWS.

mock_provider "aws" {
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

run "lock_table_uses_lockid_key" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.lock.hash_key == "LockID"
    error_message = "Terraform locking requires a LockID hash key."
  }

  assert {
    condition     = aws_dynamodb_table.lock.billing_mode == "PAY_PER_REQUEST"
    error_message = "The lock table must be on-demand."
  }

  assert {
    condition     = aws_dynamodb_table.lock.deletion_protection_enabled
    error_message = "The lock table must be protected from deletion by default."
  }
}

# Applied against the mocked provider only: nothing reaches AWS.
run "backend_config_points_at_the_resources" {
  command = apply

  assert {
    condition     = strcontains(output.backend_config, "circleguard-tfstate-lock")
    error_message = "backend_config must reference the lock table."
  }

  assert {
    condition     = strcontains(output.backend_config, "encrypt        = true")
    error_message = "backend_config must turn state encryption on."
  }
}
