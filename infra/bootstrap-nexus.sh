#!/usr/bin/env bash
# HU-01: Nexus Community and Docker hosted registry on the existing TEC-04 EC2.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap-common.sh
source "$HERE/bootstrap-common.sh"
bootstrap_require
bootstrap_target nexus

bootstrap_ssh 'command -v openssl >/dev/null && command -v python3 >/dev/null && sudo docker compose version >/dev/null' \
  || die 'Nexus EC2 missing Docker Compose, OpenSSL, or Python 3'

bootstrap_ssh 'bash -s' <<'REMOTE'
set -euo pipefail
base=/opt/circleguard/nexus
sudo install -d -m 0750 "$base"
if ! sudo test -f "$base/nexus.secrets.env"; then
  umask 077
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  printf 'NEXUS_ADMIN_PASSWORD=%s\n' "$(openssl rand -hex 24)" > "$tmp"
  printf 'NEXUS_PUBLISHER_PASSWORD=%s\n' "$(openssl rand -hex 24)" >> "$tmp"
  printf 'NEXUS_READER_PASSWORD=%s\n' "$(openssl rand -hex 24)" >> "$tmp"
  sudo install -m 0600 -o root -g root "$tmp" "$base/nexus.secrets.env"
  echo 'Generated Nexus admin/publisher/reader credentials on EC2.'
else
  echo 'Existing Nexus credentials retained.'
fi
REMOTE

src="$HERE/bootstrap/nexus"
dst=/opt/circleguard/nexus
bootstrap_upload "$src/compose.yaml" "$dst/compose.yaml"
bootstrap_upload "$src/configure.py" "$dst/configure.py"
bootstrap_ssh "cd '$dst' && sudo docker compose -f compose.yaml config --quiet && sudo docker compose -f compose.yaml up -d"
bootstrap_ssh "sudo python3 '$dst/configure.py'"
bootstrap_ssh "cd '$dst' && sudo docker compose -f compose.yaml ps"
printf 'Nexus URL: http://%s:8081 (admin restricted by TEC-04 SG)\n' "$BOOTSTRAP_TARGET_IP"
printf 'Nexus Docker Registry: %s:8082 (HTTP connector; no remote Docker login before TLS or lab-only allowance)\n' "$BOOTSTRAP_TARGET_IP"
