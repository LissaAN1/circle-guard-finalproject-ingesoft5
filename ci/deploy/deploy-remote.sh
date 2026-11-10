#!/usr/bin/env bash
# Runs ON the target EC2. Called by cgDeploy in the Jenkins pipeline.
# Validates the candidate release before applying it and attempts rollback on failure.
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
env_file="$remote/.env"

[[ -f "$env_file" ]] || {
  echo "Environment .env not found at $env_file" >&2
  exit 1
}

[[ -f "$remote/compose.base.yaml" ]] || {
  echo "Base Compose file not found" >&2
  exit 1
}

[[ -f "$remote/compose.$env_name.yaml" ]] || {
  echo "Environment Compose file not found" >&2
  exit 1
}

# Prevent concurrent deployments to the same environment.
exec 9>"$remote/.deploy-$env_name.lock"
flock -n 9 || {
  echo "Another deployment is already running for $env_name" >&2
  exit 1
}

# Read the previous application version without printing secrets.
version_count="$(grep -c '^APP_VERSION=' "$env_file" || true)"

[[ "$version_count" == "1" ]] || {
  echo "Expected exactly one APP_VERSION entry in .env" >&2
  exit 1
}

old_version="$(sed -n 's/^APP_VERSION=//p' "$env_file")"

[[ -n "$old_version" ]] || {
  echo "Current APP_VERSION is empty; rollback cannot be prepared" >&2
  exit 1
}

echo "Deploying $env_name: $old_version -> $app_version"

# Keep private temporary files inside the protected environment directory.
backup="$(mktemp "$remote/.env.backup.XXXXXXXX")"
candidate="$(mktemp "$remote/.env.candidate.XXXXXXXX")"

# Preserve the original ownership and file permissions.
cp -p -- "$env_file" "$backup"
cp -p -- "$env_file" "$candidate"

sed -i "s|^APP_VERSION=.*|APP_VERSION=$app_version|" "$candidate"

# Explicit list of application images managed by this release.
app_services=(
  auth
  identity
  promotion
  form
  gateway
  web
)

# Build Compose arguments without relying on word splitting.
compose_files=(
  -p "circleguard-$env_name"
  -f "$remote/compose.base.yaml"
  -f "$remote/compose.$env_name.yaml"
)

compose_candidate=(
  docker compose
  "${compose_files[@]}"
  --env-file "$candidate"
)

compose_active=(
  docker compose
  "${compose_files[@]}"
  --env-file "$env_file"
)

applied=false

cleanup() {
  local status=$?
  trap - EXIT
  set +e

  if [[ "$status" -ne 0 && "$applied" == true ]]; then
    echo "Deployment failed. Attempting rollback to $old_version" >&2

    # Restore the original environment configuration.
    if cp -p -- "$backup" "$env_file"; then
      echo "Previous .env restored" >&2

      if "${compose_active[@]}" up \
          -d --no-build --wait --wait-timeout 600; then
        echo "Rollback completed: $old_version" >&2
      else
        echo "CRITICAL: rollback failed; manual recovery required" >&2
        "${compose_active[@]}" ps >&2 || true
      fi
    else
      echo "CRITICAL: unable to restore .env" >&2
    fi
  fi

  rm -f -- "$candidate"

  if [[ "$status" -eq 0 ]]; then
    rm -f -- "$backup"
  else
    echo "Previous configuration backup: $backup" >&2
  fi

  exit "$status"
}

trap cleanup EXIT

# Phase 1: validate the candidate without changing the active version.
echo "Validating candidate Compose configuration..."

"${compose_candidate[@]}" config --quiet

echo "Checking candidate images in Nexus..."

# Pull only CircleGuard application images.
# Do not update databases or infrastructure images.
"${compose_candidate[@]}" pull --no-deps "${app_services[@]}"

# Phase 2: apply the previously validated candidate.
echo "Candidate validated. Applying $app_version..."

# Atomic replacement within the same filesystem.
mv -f -- "$candidate" "$env_file"
applied=true

# Phase 3: wait for startup and healthchecks.
"${compose_active[@]}" up \
  -d --no-build --wait --wait-timeout 600

echo "Deploy $env_name -> $app_version complete."
"${compose_active[@]}" ps
