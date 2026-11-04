#!/usr/bin/env bash
# DESTRUCTIVE: terminates all project instances and deletes the security groups.
# Requires --yes. The key pair is kept unless --delete-key is also given.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_aws
[[ "${1:-}" == "--yes" ]] || die "refusing without --yes (this terminates all $PROJECT servers)"
ids=$(aws ec2 describe-instances --filters "Name=tag:Project,Values=$PROJECT" \
  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
if [[ -n "$ids" ]]; then
  # shellcheck disable=SC2086
  aws ec2 terminate-instances --instance-ids $ids >/dev/null
  # shellcheck disable=SC2086
  aws ec2 wait instance-terminated --instance-ids $ids
  log "instances terminated"
fi
# SGs reference each other (env <-> cicd), so revoke every ingress rule first
for k in cicd dev stage prod; do
  id="$(sg_id "$k")"; [[ -n "$id" ]] || continue
  rules=$(aws ec2 describe-security-groups --group-ids "$id" --query 'SecurityGroups[0].IpPermissions' --output json)
  [[ "$rules" == "[]" ]] || aws ec2 revoke-security-group-ingress --group-id "$id" --ip-permissions "$rules" >/dev/null
done
for k in dev stage prod cicd; do
  id="$(sg_id "$k")"; [[ -n "$id" ]] || continue
  aws ec2 delete-security-group --group-id "$id" && log "deleted $(sg_name "$k")"
done
if [[ "${2:-}" == "--delete-key" ]]; then
  aws ec2 delete-key-pair --key-name "$KEY_NAME"; log "key pair deleted (local .pem untouched)"
fi
