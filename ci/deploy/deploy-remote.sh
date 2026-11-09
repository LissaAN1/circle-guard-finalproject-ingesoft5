#!/usr/bin/env bash
# Runs ON the target EC2. Called by cgDeploy in the Jenkins pipeline.
# Updates APP_VERSION in the environment .env and restarts the services.
set -euo pipefail

env_name="${1:-}"
app_version="${2:-}"

case "$env_name" in
  dev|stage|prod) ;;
  *) echo "Usage: deploy-remote.sh dev|stage|prod <version>" >&2; exit 2 ;;
esac

[[ -n "$app_version" ]] || { echo "app_version is required" >&2; exit 2; }
[[ "$app_version" =~ ^[0-9A-Za-z][0-9A-Za-z._+\-]{0,127}$ ]] || {
  echo "Invalid app_version: $app_version" >&2; exit 2
}

remote=/opt/circleguard/environments
[[ -f "$remote/.env" ]] || { echo "Environment .env not found at $remote/.env" >&2; exit 1; }

old_version="$(sudo grep -oP '(?<=^APP_VERSION=).*' "$remote/.env" || echo '(unknown)')"
echo "Deploying $env_name: $old_version -> $app_version"

sudo sed -i "s|^APP_VERSION=.*|APP_VERSION=$app_version|" "$remote/.env"

compose="sudo docker compose -p circleguard-$env_name \
  --env-file $remote/.env \
  -f $remote/compose.base.yaml \
  -f $remote/compose.$env_name.yaml"

$compose pull
$compose up -d --no-build
echo "Deploy $env_name -> $app_version complete."
$compose ps
