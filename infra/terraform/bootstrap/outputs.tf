output "state_bucket_name" {
  description = "Bucket that stores the Terraform state of every environment."
  value       = module.state_bucket.bucket_name
}

output "lock_table_name" {
  description = "DynamoDB table used for state locking."
  value       = aws_dynamodb_table.lock.name
}

output "region" {
  description = "Region of the backend resources."
  value       = var.region
}

output "backend_config" {
  description = "Ready-to-paste values for backend.hcl (the key is set per environment)."
  value       = <<-EOT
    bucket         = "${module.state_bucket.bucket_name}"
    region         = "${var.region}"
    dynamodb_table = "${aws_dynamodb_table.lock.name}"
    encrypt        = true
  EOT
}
