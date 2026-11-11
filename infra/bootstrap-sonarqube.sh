#!/usr/bin/env bash
# HU-01: idempotent SonarQube + PostgreSQL bootstrap on TEC-04's EC2.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap-common.sh
source "$HERE/bootstrap-common.sh"
bootstrap_require
bootstrap_target sonarqube

bootstrap_ssh 'command -v openssl >/dev/null && command -v python3 >/dev/null && sudo docker compose version >/dev/null' \
  || die 'Sonar EC2 missing Docker Compose, OpenSSL, or Python 3; inspect TEC-04 cloud-init'

bootstrap_ssh 'bash -s' <<'REMOTE'
set -euo pipefail
base=/opt/circleguard/sonarqube
sudo install -d -m 0750 "$base"
if ! sudo test -f "$base/sonar.secrets.env"; then
  umask 077
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  printf 'SONAR_DB_PASSWORD=%s\n' "$(openssl rand -hex 24)" > "$tmp"
  printf 'SONAR_ADMIN_PASSWORD=Aa1!%s\n' "$(openssl rand -hex 24)" >> "$tmp"
  sudo install -m 0600 -o root -g root "$tmp" "$base/sonar.secrets.env"
  echo 'New SonarQube credentials generated on EC2 (values not displayed).'
else
  echo 'Existing SonarQube credentials preserved.'
fi

# SonarQube's Elasticsearch requires kernel settings on the EC2 host, not in a container.
printf 'vm.max_map_count=524288\nfs.file-max=131072\n' \
  | sudo tee /etc/sysctl.d/90-circleguard-sonarqube.conf >/dev/null
sudo sysctl -p /etc/sysctl.d/90-circleguard-sonarqube.conf >/dev/null
REMOTE

src="$HERE/bootstrap/sonarqube"
dst=/opt/circleguard/sonarqube
bootstrap_upload "$src/compose.yaml" "$dst/compose.yaml"
bootstrap_upload "$src/configure.py" "$dst/configure.py"

bootstrap_ssh "sudo sh -c 'cd \"$dst\" && docker compose --env-file sonar.secrets.env -f compose.yaml config --quiet && docker compose --env-file sonar.secrets.env -f compose.yaml up -d'"
bootstrap_ssh "sudo python3 '$dst/configure.py'"
bootstrap_ssh "sudo sh -c 'cd \"$dst\" && docker compose --env-file sonar.secrets.env -f compose.yaml ps'"
printf 'SonarQube URL: http://%s:9000 (subject to TEC-04 Security Group)\n' "$BOOTSTRAP_TARGET_IP"
