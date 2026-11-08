#!/usr/bin/env bash
# Read-only availability/capacity report: does not start, stop or resize EC2.
set -euo pipefail
INFRA="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$INFRA/lib.sh"
require_aws
for env in dev stage prod; do
  id="$(instance_id "$env")"
  if [[ -z "$id" ]]; then
    echo "$env: missing EC2"
    continue
  fi
  aws ec2 describe-instances --instance-ids "$id" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,InstanceType,State.Name,PublicIpAddress]' \
    --output table
done
