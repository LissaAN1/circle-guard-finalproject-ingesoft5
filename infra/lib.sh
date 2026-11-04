#!/usr/bin/env bash
# Shared helpers. Source this file; do not execute it.
set -euo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "$INFRA_DIR/config.env"
export AWS_DEFAULT_REGION="$AWS_REGION"
export AWS_PAGER=""

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_aws() {
  command -v aws >/dev/null || die "aws CLI not found (see infra/README.md)"
  aws sts get-caller-identity --query Arn --output text >/dev/null 2>&1 \
    || die "AWS credentials not configured. Run: aws configure"
}

my_ip() { curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]'; }

default_vpc() {
  aws ec2 describe-vpcs --filters Name=isDefault,Values=true \
    --query 'Vpcs[0].VpcId' --output text
}

sg_name() { echo "${PROJECT}-sg-$1"; }   # $1: cicd|dev|stage|prod

sg_id() {
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$(sg_name "$1")" "Name=vpc-id,Values=$(default_vpc)" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null | sed 's/^None$//'
}

# Instance id for a server name in a non-terminated state (empty if none)
instance_id() {
  aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${PROJECT}-$1" "Name=tag:Project,Values=${PROJECT}" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text | awk '{print $1}'
}

server_field() { # $1 server name, $2 index (1 name,2 type,3 disk,4 swap)
  local s; for s in "${SERVERS[@]}"; do
    IFS=: read -r n t d w <<<"$s"
    if [[ "$n" == "$1" ]]; then
      case "$2" in 1) echo "$n";; 2) echo "$t";; 3) echo "$d";; 4) echo "$w";; esac
      return
    fi
  done
}

all_server_names() { local s; for s in "${SERVERS[@]}"; do echo "${s%%:*}"; done; }

# Add an ingress rule, ignoring "already exists" so scripts are idempotent
# usage: allow <sg-id> <port> <cidr:CIDR|sg:SGID> [description]
allow() {
  local sg="$1" port="$2" src="$3" desc="${4:-}" out
  local perm
  case "$src" in
    cidr:*) perm="IpProtocol=tcp,FromPort=$port,ToPort=$port,IpRanges=[{CidrIp=${src#cidr:},Description=\"$desc\"}]";;
    sg:*)   perm="IpProtocol=tcp,FromPort=$port,ToPort=$port,UserIdGroupPairs=[{GroupId=${src#sg:},Description=\"$desc\"}]";;
    *) die "bad source $src";;
  esac
  if ! out=$(aws ec2 authorize-security-group-ingress --group-id "$sg" \
        --ip-permissions "$perm" 2>&1); then
    [[ "$out" == *InvalidPermission.Duplicate* ]] || die "$out"
  fi
}
