#!/usr/bin/env bash
# HU-04: runs ON the Jenkins EC2 (uploaded and executed by infra/bootstrap-ci.sh).
# Reads optional KEY=VALUE lines from stdin: GITHUB_TOKEN, NEXUS_PUBLISHER_PASSWORD, SMEE_URL,
# NEXUS_REGISTRY (host:port), JENKINS_PUBLIC_URL. Missing keys keep their previous value.
# Idempotent: reruns reuse the existing controller, volumes, agent secret and credentials.
set -euo pipefail

DIR=/opt/circleguard/jenkins
SECRETS="$DIR/ci.secrets.env"       # 0600 root: tokens and passwords (never in Git or argv)
ENVFILE="$DIR/.env"                 # compose interpolation (non-secret)
AGENT_SECRET_FILE="$DIR/agent.secrets.env"
CASC_CREDS="$DIR/casc.d/20-credentials.yaml"
COMPOSE=(docker compose -f "$DIR/compose.yaml")

[[ "$(id -u)" -eq 0 ]] || { echo 'ERROR: run as root (sudo)' >&2; exit 1; }
install -d -m 0750 "$DIR" "$DIR/casc.d"
touch "$SECRETS" "$ENVFILE"; chmod 600 "$SECRETS"; chmod 644 "$ENVFILE"

# get/set KEY=VALUE in a file without printing values
get() { sed -n "s/^$2=//p" "$1" | tail -n1; }
set_kv() { # file key value
  local tmp; tmp="$(mktemp)"
  grep -v "^$2=" "$1" > "$tmp" || true
  printf '%s=%s\n' "$2" "$3" >> "$tmp"
  cat "$tmp" > "$1"; rm -f "$tmp"
}

# 1) Optional inputs from stdin
declare -A IN=()
if [[ ! -t 0 ]]; then
  while IFS='=' read -r k v; do
    [[ "$k" =~ ^(GITHUB_TOKEN|NEXUS_PUBLISHER_PASSWORD|SMEE_URL|NEXUS_REGISTRY|JENKINS_PUBLIC_URL)$ ]] && IN[$k]="$v"
  done
fi
for k in GITHUB_TOKEN NEXUS_PUBLISHER_PASSWORD SMEE_URL; do
  [[ -n "${IN[$k]:-}" ]] && set_kv "$SECRETS" "$k" "${IN[$k]}"
done
for k in NEXUS_REGISTRY JENKINS_PUBLIC_URL; do
  [[ -n "${IN[$k]:-}" ]] && set_kv "$ENVFILE" "$k" "${IN[$k]}"
done

# 2) Build-agent access to the host Docker daemon without root
set_kv "$ENVFILE" DOCKER_GID "$(getent group docker | cut -d: -f3)"

# 3) Jenkins credentials (JCasC) only for the secrets that exist
{
  printf 'credentials:\n  system:\n    domainCredentials:\n      - credentials:\n'
  if [[ -n "$(get "$SECRETS" GITHUB_TOKEN)" ]]; then
    printf '          - string:\n              scope: GLOBAL\n              id: "github-token"\n'
    printf '              secret: "${GITHUB_TOKEN}"\n              description: "GitHub token (scan, commit status, webhooks)"\n'
  fi
  if [[ -n "$(get "$SECRETS" NEXUS_PUBLISHER_PASSWORD)" ]]; then
    printf '          - usernamePassword:\n              scope: GLOBAL\n              id: "nexus-publisher"\n'
    printf '              username: "cg-publisher"\n              password: "${NEXUS_PUBLISHER_PASSWORD}"\n'
    printf '              description: "Nexus Docker publisher (HU-01 role circleguard-publisher)"\n'
  fi
} > "$CASC_CREDS.new"
if grep -q 'id:' "$CASC_CREDS.new"; then mv "$CASC_CREDS.new" "$CASC_CREDS"; chmod 644 "$CASC_CREDS"
else rm -f "$CASC_CREDS.new" "$CASC_CREDS"; fi

# 4) Nexus registry is plain HTTP inside the VPC: trust it in the host daemon (restart only if it changed)
registry="$(get "$ENVFILE" NEXUS_REGISTRY)"
if [[ -n "$registry" ]]; then
  result="$(python3 - "$registry" <<'PY'
import json, os, sys
path, reg = "/etc/docker/daemon.json", sys.argv[1]
cfg = json.load(open(path)) if os.path.exists(path) and os.path.getsize(path) else {}
regs = cfg.setdefault("insecure-registries", [])
if reg in regs:
    print("UNCHANGED"); sys.exit(0)
regs.append(reg)
json.dump(cfg, open(path, "w"), indent=2)
print("CHANGED")
PY
)"
  if [[ "$result" == CHANGED ]]; then
    echo "Docker daemon now trusts $registry; restarting Docker (containers restart automatically)"
    systemctl restart docker
  else
    echo "Docker daemon already trusts $registry"
  fi
fi

# 5) Controller (picks up new plugins, casc.d, credentials)
"${COMPOSE[@]}" config --quiet
"${COMPOSE[@]}" build jenkins

# Pre-flight: a throwaway container must accept the new JCasC files before production is touched,
# so a bad config can never replace the working HU-01 controller.
echo 'Pre-flight: validating casc.d in a throwaway container...'
image="$("${COMPOSE[@]}" config --images | grep jenkins-bootstrap | head -n1)"
probe="cg-casc-probe-$$"
docker rm -f "$probe" >/dev/null 2>&1 || true
docker run -d --name "$probe" --memory 900m \
  -e CASC_JENKINS_CONFIG=/etc/jenkins/casc.yaml,/etc/jenkins/casc.d \
  -e JAVA_OPTS='-Djenkins.install.runSetupWizard=false -Xmx512m' \
  -e JENKINS_ADMIN_USER=probe -e JENKINS_ADMIN_PASSWORD=probe-not-a-secret \
  -e JENKINS_TEACHER_USER=probe-teacher -e JENKINS_TEACHER_PASSWORD=probe-not-a-secret \
  -e GITHUB_TOKEN=probe -e NEXUS_PUBLISHER_PASSWORD=probe \
  -e JENKINS_PUBLIC_URL=http://localhost:8080/ -e NEXUS_REGISTRY= \
  -v "$DIR/casc.yaml:/etc/jenkins/casc.yaml:ro" -v "$DIR/casc.d:/etc/jenkins/casc.d:ro" \
  "$image" >/dev/null
verdict=timeout
for _ in $(seq 1 40); do
  logs="$(docker logs "$probe" 2>&1 || true)"
  if grep -q 'ConfiguratorException' <<<"$logs"; then verdict=invalid; break; fi
  if grep -q 'Jenkins is fully up and running' <<<"$logs"; then verdict=valid; break; fi
  sleep 5
done
if [[ "$verdict" != valid ]]; then
  echo "ERROR: pre-flight verdict=$verdict; production Jenkins was NOT touched. Relevant log lines:" >&2
  docker logs "$probe" 2>&1 | grep -E 'ConfiguratorException|WARNING|SEVERE|Caused by' | head -n 25 >&2 || true
  docker rm -f "$probe" >/dev/null 2>&1 || true
  exit 1
fi
docker rm -f "$probe" >/dev/null 2>&1 || true
echo 'Pre-flight OK.'

"${COMPOSE[@]}" up -d jenkins
echo 'Waiting for the controller to be healthy...'
for _ in $(seq 1 60); do
  [[ "$(docker inspect -f '{{.State.Health.Status}}' circleguard-jenkins 2>/dev/null)" == healthy ]] && break
  sleep 10
done
[[ "$(docker inspect -f '{{.State.Health.Status}}' circleguard-jenkins)" == healthy ]] \
  || { echo 'ERROR: controller is not healthy; docker logs circleguard-jenkins' >&2; exit 1; }

# 6) Inbound agent secret (read from the controller; never printed)
admin_pw="$(get "$DIR/jenkins.secrets.env" JENKINS_ADMIN_PASSWORD)"
secret=""
for _ in $(seq 1 12); do
  secret="$(printf 'user = "admin:%s"\n' "$admin_pw" \
    | curl -fsS -K - "http://127.0.0.1:8080/computer/build-agent/jenkins-agent.jnlp" 2>/dev/null \
    | grep -oE '[0-9a-f]{64}' | head -n1 || true)"
  [[ -n "$secret" ]] && break
  sleep 5
done
[[ -n "$secret" ]] || { echo 'ERROR: node build-agent not found; check casc.d/10-ci.yaml loaded (docker logs circleguard-jenkins)' >&2; exit 1; }
if [[ "$(get "$AGENT_SECRET_FILE" JENKINS_SECRET 2>/dev/null || true)" != "$secret" ]]; then
  umask 077; printf 'JENKINS_SECRET=%s\n' "$secret" > "$AGENT_SECRET_FILE"
fi

# 7) Agent, and the optional webhook relay
"${COMPOSE[@]}" --profile ci up -d --build build-agent
if [[ -n "$(get "$SECRETS" SMEE_URL)" ]]; then
  "${COMPOSE[@]}" --profile webhook up -d webhook-relay
fi

"${COMPOSE[@]}" --profile ci --profile webhook ps
echo 'HU-04 CI stack applied.'
