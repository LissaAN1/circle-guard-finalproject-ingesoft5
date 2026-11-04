#!/usr/bin/env bash
# Lists project servers with state and addresses (public IPs change on stop/start).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_aws
aws ec2 describe-instances --filters "Name=tag:Project,Values=$PROJECT" \
  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,InstanceId,InstanceType,State.Name,PublicIpAddress,PrivateIpAddress]' \
  --output table
