#!/usr/bin/env bash
# Deploy one approved environment to an existing TEC-04 EC2.
# No EC2 creation, Docker build, registry configuration, or volume deletion.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA="$(dirname "$HERE")"
env="${1:-}"
case "$env" in
  dev|stage|prod) ;;
  *) echo 'Usage: bash infra/environments/deploy-env.sh dev|stage|prod' >&2; exit 2 ;;
esac
[[ -r "$HERE/.env.$env" ]] || { echo 'Missing private environment file' >&2; exit 1; }
bash "$HERE/validate.sh" "$env" >/dev/null
# shellcheck source=../lib.sh
source "$INFRA/lib.sh"
require_aws
instance="$(instance_id "$env")"
[[ -n "$instance" ]] || die "EC2 for $env not found; TEC-04 must provision it"
state="$(aws ec2 describe-instances --instance-ids "$instance" --query 'Reservations[0].Instances[0].State.Name' --output text)"
[[ "$state" == running ]] || die "EC2 $env is $state; request authorized start"
ip="$(aws ec2 describe-instances --instance-ids "$instance" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
[[ -n "$ip" && "$ip" != None ]] || die "EC2 $env has no public IPv4"
key="${CIRCLEGUARD_SSH_KEY:-${KEY_DIR}/${KEY_NAME}.pem}"
[[ -r "$key" ]] || die "SSH key not readable at configured path"
ssh_options=(-i "$key" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
ssh_to() { ssh "${ssh_options[@]}" "ubuntu@$ip" "$@"; }
scpto() { scp -q "${ssh_options[@]}" "$1" "ubuntu@$ip:$2"; }
# Intentional conservative gate: t3.small (2 GiB) must not run this stack.
mem_kib="$(ssh_to "awk '/MemTotal/ {print \$2}' /proc/meminfo")"
[[ "$mem_kib" =~ ^[0-9]+$ ]] || die 'Cannot read EC2 memory'
if (( mem_kib < 7340032 )); then
  die "Insufficient RAM on $env ($((mem_kib / 1024)) MiB). Review capacity and costs with TEC-04; no deployment was made."
fi
ssh_to 'sudo docker compose version >/dev/null' || die 'Docker Compose unavailable on EC2'
remote=/opt/circleguard/environments
ssh_to "sudo install -d -m 0700 '$remote'"
# Never overwrite a different remote secret file, even on redeploy.
local_hash="$(sha256sum "$HERE/.env.$env" | awk '{print $1}')"
remote_hash="$(ssh_to "if sudo test -f '$remote/.env'; then sudo sha256sum '$remote/.env' | awk '{print \$1}'; fi")"
if [[ -n "$remote_hash" && "$local_hash" != "$remote_hash" ]]; then
  die "Remote $env secrets differ from the local file. Resolve manually before deploying; none were overwritten."
fi
for file in compose.base.yaml "compose.$env.yaml" init-db.sql; do
  tmp="/tmp/cg-hu02-${env}-${file}"
  scpto "$HERE/$file" "$tmp"
  ssh_to "sudo install -m 0644 '$tmp' '$remote/$file' && rm -f '$tmp'"
done
if [[ -z "$remote_hash" ]]; then
  # SSH stdin goes straight to a root-owned file. No world-readable /tmp copy.
  ssh_to "sudo sh -c 'umask 077; cat > $remote/.env'" < "$HERE/.env.$env"
fi
registry="$(sed -n 's/^REGISTRY=//p' "$HERE/.env.$env")"
# Docker registry must be reachable on the approved private network.
# Docker Engine must already trust the approved HTTPS CA or private lab HTTP endpoint.
if [[ -z "${NEXUS_READER_PASSWORD:-}" ]]; then
  read -r -s -p 'Nexus cg-reader password (hidden): ' NEXUS_READER_PASSWORD
  printf '\n'
fi
[[ -n "$NEXUS_READER_PASSWORD" ]] || die 'Nexus reader password is required'
printf '%s\n' "$NEXUS_READER_PASSWORD" | ssh_to "sudo docker login '$registry' -u cg-reader --password-stdin >/dev/null"
unset NEXUS_READER_PASSWORD
compose="sudo docker compose -p circleguard-$env --env-file '$remote/.env' -f '$remote/compose.base.yaml' -f '$remote/compose.$env.yaml'"
ssh_to "$compose config --quiet"
ssh_to "$compose pull"
ssh_to "$compose up -d --no-build"
ssh_to "$compose ps"
echo "HU-02 environment $env deployed without image builds. Run verify-env.sh next."
