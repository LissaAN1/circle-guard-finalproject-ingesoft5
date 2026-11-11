#!/usr/bin/env bash
# Offline checks: no AWS calls and no password disclosure.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env="${1:-}"
case "$env" in
  dev|stage|prod) ;;
  *) echo 'Usage: bash infra/environments/validate.sh dev|stage|prod' >&2; exit 2 ;;
esac
file="$HERE/.env.$env"
[[ -r "$file" ]] || { echo "Missing private $file" >&2; exit 1; }
for key in CG_ENV REGISTRY APP_VERSION WEB_BIND_IP DB_USER DB_PASSWORD NEO4J_PASSWORD LDAP_ADMIN_PASSWORD REDIS_PASSWORD JWT_SECRET QR_SECRET VAULT_SECRET VAULT_SALT VAULT_HASH_SALT; do
  grep -Eq "^${key}=[^[:space:]]+" "$file" || { echo "Missing or blank: $key" >&2; exit 1; }
done
actual="$(sed -n 's/^CG_ENV=//p' "$file")"
[[ "$actual" == "$env" ]] || { echo 'Environment mismatch' >&2; exit 1; }
grep -Eq '^APP_VERSION=[0-9]+\.[0-9]+\.[0-9]+$' "$file" || { echo 'APP_VERSION must be X.Y.Z' >&2; exit 1; }
grep -Eq '^REGISTRY=[A-Za-z0-9.-]+:[0-9]+$' "$file" || { echo 'REGISTRY must be host:port' >&2; exit 1; }
if command -v docker >/dev/null 2>&1; then
  (cd "$HERE" && docker compose --env-file ".env.$env" -f compose.base.yaml -f "compose.$env.yaml" config --quiet)
  echo "PASS: $env variables and Compose syntax"
else
  echo "PASS: $env variable format; Compose syntax not checked (Docker unavailable)"
fi
