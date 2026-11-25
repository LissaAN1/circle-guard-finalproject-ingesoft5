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

variables {
  name        = "circleguard-test"
  environment = "dev"
}

run "defaults_are_secure" {
  command = plan

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls && aws_s3_bucket_public_access_block.this.block_public_policy && aws_s3_bucket_public_access_block.this.ignore_public_acls && aws_s3_bucket_public_access_block.this.restrict_public_buckets
    error_message = "All public access must be blocked."
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be enabled by default."
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "force_destroy must be off by default."
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "circleguard-test-artifacts-123456789012"
    error_message = "Bucket name must be <name>-<purpose>-<account id>."
  }
}

run "encryption_is_enabled" {
  command = plan

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "Server-side encryption is required."
  }
}

run "custom_purpose_changes_the_name" {
  command = plan

  variables {
    purpose = "reports"
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "circleguard-test-reports-123456789012"
    error_message = "The purpose must be part of the bucket name."
  }
}

run "allows_force_destroy_in_dev" {
  command = plan

  variables {
    force_destroy = true
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy
    error_message = "force_destroy must be honored in dev."
  }
}

run "rejects_force_destroy_outside_dev" {
  command = plan

  variables {
    environment   = "prod"
    force_destroy = true
  }

  expect_failures = [var.force_destroy]
}

run "rejects_invalid_purpose" {
  command = plan

  variables {
    purpose = "Build Reports"
  }

  expect_failures = [var.purpose]
}

run "rejects_zero_noncurrent_expiration" {
  command = plan

  variables {
    noncurrent_version_expiration_days = 0
  }

  expect_failures = [var.noncurrent_version_expiration_days]
}

run "rejects_fractional_noncurrent_expiration" {
  command = plan

  variables {
    noncurrent_version_expiration_days = 2.5
  }

  expect_failures = [var.noncurrent_version_expiration_days]
}

run "rejects_unknown_environment" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}
