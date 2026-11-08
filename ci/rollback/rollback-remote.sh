#!/usr/bin/env bash
# HU-09: redeploy a specific version on a CircleGuard environment (runs ON the target EC2 via SSH).
# Usage: bash rollback-remote.sh <env> <version>
#   env     : dev | stage | prod
#   version : any published image tag, e.g. 1.0.0 or 1.0.0-ci.12.ab12cd3
set -euo pipefail
env_name="${1:?Usage: rollback-remote.sh <env> <version>}"
version="${2:?version required}"
[[ "$env_name" =~ ^(dev|stage|prod)$ ]] || { echo "Invalid env: $env_name" >&2; exit 2; }
[[ "$version" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]{0,127}$ ]] || { echo "Invalid version: $version" >&2; exit 2; }

REMOTE=/opt/circleguard/environments
ENV_FILE="$REMOTE/.env"
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE; run infra/environments/deploy-env.sh first" >&2; exit 1; }

old_version="$(grep -E '^APP_VERSION=' "$ENV_FILE" | cut -d= -f2 || echo unknown)"
echo "Rolling back $env_name: $old_version -> $version"

tmp="$(mktemp)"
grep -v '^APP_VERSION=' "$ENV_FILE" > "$tmp"
printf 'APP_VERSION=%s\n' "$version" >> "$tmp"
sudo install -m 0600 "$tmp" "$ENV_FILE"
rm -f "$tmp"

COMPOSE="docker compose -p circleguard-${env_name} --env-file ${ENV_FILE} -f ${REMOTE}/compose.base.yaml -f ${REMOTE}/compose.${env_name}.yaml"

echo "Pulling $version from registry..."
sudo $COMPOSE pull

echo "Restarting services..."
sudo $COMPOSE up -d --no-build

sudo $COMPOSE ps
echo "Rollback $env_name -> $version complete. Run verify-env.sh to confirm health."
