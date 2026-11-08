#!/usr/bin/env bash
# HU-01: helpers for deploying CI/CD tools on the EC2 hosts created by TEC-04.
set -euo pipefail

BOOTSTRAP_INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$BOOTSTRAP_INFRA_DIR/config.env" ]]; then
  printf 'ERROR: infra/config.env is missing. Verify the TEC-04 files on dev.\n' >&2
  exit 1
fi

# Reuse TEC-04 configuration, AWS helpers, and instance naming conventions.
# shellcheck source=lib.sh
source "$BOOTSTRAP_INFRA_DIR/lib.sh"

bootstrap_require() {
  local bin
  for bin in aws ssh scp curl; do
    command -v "$bin" >/dev/null 2>&1 || die "missing command: $bin"
  done
  require_aws
}

bootstrap_target() {
  local role="$1" id state addr

  id="$(instance_id "$role")"
  [[ -n "$id" ]] || die "EC2 ${PROJECT}-${role} not found; verify TEC-04"

  state="$(aws ec2 describe-instances --instance-ids "$id" \
    --query 'Reservations[0].Instances[0].State.Name' --output text)"
  [[ "$state" == running ]] || die "EC2 ${PROJECT}-${role} is ${state}; start it using infra/power.sh"

  addr="$(aws ec2 describe-instances --instance-ids "$id" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
  [[ -n "$addr" && "$addr" != None ]] || die "EC2 ${PROJECT}-${role} has no public IPv4"

  BOOTSTRAP_TARGET_IP="$addr"
  BOOTSTRAP_SSH_KEY="${CIRCLEGUARD_SSH_KEY:-${KEY_DIR}/${KEY_NAME}.pem}"

  [[ -r "$BOOTSTRAP_SSH_KEY" ]] || die "SSH key not found: $BOOTSTRAP_SSH_KEY"
}

bootstrap_ssh() {
  ssh -i "$BOOTSTRAP_SSH_KEY" -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 \
    "ubuntu@${BOOTSTRAP_TARGET_IP}" "$@"
}

bootstrap_upload() {
  local src="$1" dest="$2" tmp
  [[ -f "$src" ]] || die "missing source file: $src"

  tmp="/tmp/cg-hu01-${BASHPID}-$(basename "$src")"

  scp -q -i "$BOOTSTRAP_SSH_KEY" -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 \
    "$src" "ubuntu@${BOOTSTRAP_TARGET_IP}:${tmp}"

  bootstrap_ssh "sudo install -D -m 0644 '$tmp' '$dest' && rm -f '$tmp'"
}
