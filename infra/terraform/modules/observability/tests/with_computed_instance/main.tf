# Test helper: wires the module to an instance whose id is only known after
# apply, the same way an environment connects it to the compute module.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

resource "aws_instance" "server" {
  ami           = "ami-0123456789abcdef0"
  instance_type = "t3.micro"
}

module "observability" {
  source = "../.."

  name        = "circleguard-test"
  environment = "dev"
  services    = ["auth-service"]
  instances   = { server = aws_instance.server.id }
}

output "alarm_count" {
  value = length(module.observability.cpu_alarm_names)
}
