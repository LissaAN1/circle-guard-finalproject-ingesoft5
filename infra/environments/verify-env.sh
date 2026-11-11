#!/usr/bin/env bash
# Read-only remote readiness and image digests; output contains no secrets.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA="$(dirname "$HERE")"
env="${1:-}"
case "$env" in
  dev|stage|prod) ;;
  *) echo 'Usage: bash infra/environments/verify-env.sh dev|stage|prod' >&2; exit 2 ;;
esac
# shellcheck source=../lib.sh
source "$INFRA/lib.sh"
require_aws
instance="$(instance_id "$env")"
[[ -n "$instance" ]] || die "No EC2 for $env"
ip="$(aws ec2 describe-instances --instance-ids "$instance" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
[[ -n "$ip" && "$ip" != None ]] || die "No public IPv4 for $env"
key="${CIRCLEGUARD_SSH_KEY:-${KEY_DIR}/${KEY_NAME}.pem}"
[[ -r "$key" ]] || die 'SSH key missing'
ssh -i "$key" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "ubuntu@$ip" "bash -s -- '$env'" <<'REMOTE'
set -euo pipefail
env="$1"
remote=/opt/circleguard/environments
compose() {
  sudo docker compose -p "circleguard-$env" --env-file "$remote/.env" \
    -f "$remote/compose.base.yaml" -f "$remote/compose.$env.yaml" "$@"
}
compose ps
for service in auth identity promotion form gateway web; do
  id="$(compose ps -q "$service")"
  [[ -n "$id" ]] || { echo "MISSING $service" >&2; exit 1; }
  status="$(sudo docker inspect --format '{{.State.Health.Status}}' "$id")"
  printf '%-10s %s\n' "$service" "$status"
  [[ "$status" == healthy ]] || { echo "Unhealthy: $service" >&2; exit 1; }
done
curl -fsS -o /dev/null http://127.0.0.1:80/
echo "PASS: $env frontend HTTP, five Actuator probes, and application healthchecks"
# The same registry image digest must appear on dev/stage/prod for each service.
for service in auth identity promotion form gateway web; do
  id="$(compose ps -q "$service")"
  ref="$(sudo docker inspect --format '{{.Config.Image}}' "$id")"
  digests="$(sudo docker image inspect --format '{{join .RepoDigests ","}}' "$ref")"
  [[ -n "$digests" ]] || { echo "Missing repository digest: $service" >&2; exit 1; }
  printf 'IMAGE %s %s\n' "$service" "$digests"
done
REMOTE
