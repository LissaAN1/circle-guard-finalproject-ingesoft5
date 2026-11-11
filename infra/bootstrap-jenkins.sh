#!/usr/bin/env bash
# HU-01: reproducible, non-destructive Jenkins bootstrap on the existing TEC-04 EC2.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=bootstrap-common.sh
source "$HERE/bootstrap-common.sh"

bootstrap_require
bootstrap_target jenkins

# The teacher's Jenkins login is supplied by the operator, not invented in Git.
# Once initialized, an existing server preserves its credentials across runs.
if [[ -n "${JENKINS_TEACHER_USER:-}" ]]; then
  [[ "$JENKINS_TEACHER_USER" =~ ^[A-Za-z0-9._-]+$ ]] \
    || die 'JENKINS_TEACHER_USER must contain only letters, digits, dot, underscore or dash'
fi

bootstrap_ssh 'command -v openssl >/dev/null && sudo docker compose version >/dev/null' \
  || die 'EC2 is not ready (OpenSSL/Docker Compose); inspect TEC-04 cloud-init'

# Create once: two local Jenkins users; passwords are generated on EC2 and NEVER printed.
# Omitting JENKINS_TEACHER_USER on reruns is safe if secrets already exist.
bootstrap_ssh "bash -s -- '${JENKINS_TEACHER_USER:-}'" <<'REMOTE'
set -euo pipefail

dst=/opt/circleguard/jenkins
secrets="$dst/jenkins.secrets.env"
username="$1"

sudo install -d -m 0750 "$dst"

if sudo test -f "$secrets"; then
  old_user="$(sudo sed -n 's/^JENKINS_TEACHER_USER=//p' "$secrets")"

  if [[ -n "$username" && "$old_user" != "$username" ]]; then
    printf 'ERROR: teacher username differs from the existing Jenkins account.\n' >&2
    exit 1
  fi

  printf 'Existing Jenkins credentials kept unchanged.\n'
else
  [[ -n "$username" ]] || {
    printf 'ERROR: set JENKINS_TEACHER_USER for first initialization.\n' >&2
    exit 1
  }

  umask 077
  temp="$(mktemp)"
  trap 'rm -f "$temp"' EXIT

  printf 'JENKINS_ADMIN_USER=admin\n' > "$temp"
  printf 'JENKINS_ADMIN_PASSWORD=%s\n' "$(openssl rand -hex 24)" >> "$temp"
  printf 'JENKINS_TEACHER_USER=%s\n' "$username" >> "$temp"
  printf 'JENKINS_TEACHER_PASSWORD=%s\n' "$(openssl rand -hex 24)" >> "$temp"

  sudo install -m 0600 -o root -g root "$temp" "$secrets"

  printf 'Generated local Jenkins credentials on EC2 (not displayed).\n'
fi
REMOTE

src="$HERE/bootstrap/jenkins"
dst=/opt/circleguard/jenkins

bootstrap_upload "$src/Dockerfile" "$dst/Dockerfile"
bootstrap_upload "$src/compose.yaml" "$dst/compose.yaml"
bootstrap_upload "$src/casc.yaml" "$dst/casc.yaml"
# HU-04 files referenced by compose.yaml (casc.d mount and the build-agent image context)
bootstrap_upload "$src/casc.d/10-ci.yaml" "$dst/casc.d/10-ci.yaml"
bootstrap_upload "$src/agent/Dockerfile" "$dst/agent/Dockerfile"

# The base image is pinned. Repeated Compose up reuses the same container and volume.
bootstrap_ssh "sudo sh -c 'cd \"$dst\" && docker compose -f compose.yaml config --quiet && docker compose -f compose.yaml up -d --build'"

bootstrap_ssh "sudo docker compose -f '$dst/compose.yaml' ps"

printf 'Jenkins URL: http://%s:8080 (only when allowed by the EC2 security group)\n' "$BOOTSTRAP_TARGET_IP"
printf 'Credentials remain on EC2 at %s/jenkins.secrets.env. Do not post them to Jira.\n' "$dst"
