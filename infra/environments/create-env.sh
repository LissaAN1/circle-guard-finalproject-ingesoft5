#!/usr/bin/env bash
# Create a private local configuration once. Never overwrite existing values.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env="${1:-}"
case "$env" in
  dev|stage|prod) ;;
  *) echo 'Usage: bash infra/environments/create-env.sh dev|stage|prod' >&2; exit 2 ;;
esac
command -v openssl >/dev/null 2>&1 || { echo 'OpenSSL missing' >&2; exit 1; }
file="$HERE/.env.$env"
if [[ -e "$file" ]]; then
  printf 'Preserved existing private file: %s\n' "$file"
  exit 0
fi
umask 077
{
  printf 'CG_ENV=%s\n' "$env"
  printf 'REGISTRY=\nAPP_VERSION=\nWEB_BIND_IP=127.0.0.1\nDB_USER=cg_app\n'
  for name in DB_PASSWORD NEO4J_PASSWORD LDAP_ADMIN_PASSWORD REDIS_PASSWORD JWT_SECRET QR_SECRET VAULT_SECRET VAULT_HASH_SALT; do
    printf '%s=%s\n' "$name" "$(openssl rand -hex 32)"
  done
  printf 'VAULT_SALT=%s\n' "$(openssl rand -hex 8)"
} > "$file"
chmod 600 "$file"
printf 'Created %s (mode 0600). Set REGISTRY and APP_VERSION privately.\n' "$file"
