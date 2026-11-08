#!/usr/bin/env bash
# HU-04/HU-08/HU-09: runs ON the Jenkins EC2 (uploaded and executed by infra/bootstrap-ci.sh).
# Reads optional KEY=VALUE lines from stdin. Missing keys keep their previous value.
# Accepted keys: GITHUB_TOKEN, NEXUS_PUBLISHER_PASSWORD, SMEE_URL, NEXUS_REGISTRY,
#   JENKINS_PUBLIC_URL, NOTIFY_WEBHOOK_URL, EC2_DEV_HOST, EC2_STAGE_HOST, EC2_PROD_HOST,
#   EC2_SSH_KEY_B64 (base64-encoded PEM; enables the deploy/rollback SSH credential).
# Idempotent: reruns reuse the existing controller, volumes, agent secret and credentials.
set -euo pipefail

DIR=/opt/circleguard/jenkins
SECRETS="$DIR/ci.secrets.env"       # 0600 root: tokens and passwords (never in Git or argv)
ENVFILE="$DIR/.env"                 # compose interpolation (non-secret)
EC2_KEY_FILE="$DIR/ec2-key.pem"     # SSH private key bind-mounted into the container at /run/secrets/ec2-key.pem
AGENT_SECRET_FILE="$DIR/agent.secrets.env"
CASC_CREDS="$DIR/casc.d/20-credentials.yaml"
COMPOSE=(docker compose -f "$DIR/compose.yaml")

[[ "$(id -u)" -eq 0 ]] || { echo 'ERROR: run as root (sudo)' >&2; exit 1; }
install -d -m 0750 "$DIR"
# casc.d is bind-mounted and read by the non-root jenkins user; it holds no secrets (only ${VAR} refs)
install -d -m 0755 "$DIR/casc.d"
touch "$SECRETS" "$ENVFILE"; chmod 600 "$SECRETS"; chmod 644 "$ENVFILE"
# ec2-key.pem must exist before compose starts (bind mount source). Placeholder is empty
# until EC2_SSH_KEY_B64 is provided; chown 1000 so the jenkins user inside the container can read it.
[[ -f "$EC2_KEY_FILE" ]] || install -m 0400 -o 1000 -g 1000 /dev/null "$EC2_KEY_FILE"

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
    [[ "$k" =~ ^(GITHUB_TOKEN|NEXUS_PUBLISHER_PASSWORD|SMEE_URL|NEXUS_REGISTRY|JENKINS_PUBLIC_URL|NOTIFY_WEBHOOK_URL|EC2_DEV_HOST|EC2_STAGE_HOST|EC2_PROD_HOST|EC2_SSH_KEY_B64)$ ]] && IN[$k]="$v"
  done
fi
for k in GITHUB_TOKEN NEXUS_PUBLISHER_PASSWORD SMEE_URL NOTIFY_WEBHOOK_URL; do
  [[ -n "${IN[$k]:-}" ]] && set_kv "$SECRETS" "$k" "${IN[$k]}"
done
for k in NEXUS_REGISTRY JENKINS_PUBLIC_URL EC2_DEV_HOST EC2_STAGE_HOST EC2_PROD_HOST; do
  [[ -n "${IN[$k]:-}" ]] && set_kv "$ENVFILE" "$k" "${IN[$k]}"
done

# EC2 SSH key (base64-encoded to survive KEY=VALUE stdin). Written to the host path that is
# bind-mounted into the container at /run/secrets/ec2-key.pem; owned by jenkins uid 1000 (0400).
if [[ -n "${IN[EC2_SSH_KEY_B64]:-}" ]]; then
  printf '%s' "${IN[EC2_SSH_KEY_B64]}" | base64 -d > "$EC2_KEY_FILE"
  chown 1000:1000 "$EC2_KEY_FILE"; chmod 0400 "$EC2_KEY_FILE"
  echo "EC2 SSH key stored at $EC2_KEY_FILE (uid 1000, 0400)"
fi

# 2) Build-agent access to the host Docker daemon without root
set_kv "$ENVFILE" DOCKER_GID "$(getent group docker | cut -d: -f3)"

# 3) Jenkins credentials (JCasC) only for the secrets that exist
{
  printf 'credentials:\n  system:\n    domainCredentials:\n      - credentials:\n'
  if [[ -n "$(get "$SECRETS" GITHUB_TOKEN)" ]]; then
    printf '          - string:\n              scope: GLOBAL\n              id: "github-token"\n'
    printf '              secret: "${GITHUB_TOKEN}"\n              description: "GitHub token as secret text (commit status from pipeline steps)"\n'
    # GitHub Branch Source ignores Secret text and scans anonymously (60 calls/hour); it needs a
    # username/password credential whose password is the token.
    printf '          - usernamePassword:\n              scope: GLOBAL\n              id: "github-scan"\n'
    printf '              username: "DanielTRUJILLO2"\n              password: "${GITHUB_TOKEN}"\n'
    printf '              description: "GitHub token for the multibranch scan and webhooks"\n'
  fi
  if [[ -n "$(get "$SECRETS" NEXUS_PUBLISHER_PASSWORD)" ]]; then
    printf '          - usernamePassword:\n              scope: GLOBAL\n              id: "nexus-publisher"\n'
    printf '              username: "cg-publisher"\n              password: "${NEXUS_PUBLISHER_PASSWORD}"\n'
    printf '              description: "Nexus Docker publisher (HU-01 role circleguard-publisher)"\n'
  fi
  # SSH key for deploy/rollback jobs. Use the container-side mount path, not the host path.
  # -s checks the file is non-empty (placeholder is empty until EC2_SSH_KEY_B64 is provided).
  if [[ -s "$EC2_KEY_FILE" ]]; then
    printf '          - basicSSHUserPrivateKey:\n              scope: GLOBAL\n              id: "ec2-ssh-key"\n'
    printf '              username: "ubuntu"\n              description: "EC2 SSH key for deploy and rollback (HU-08/HU-09)"\n'
    printf '              privateKeySource:\n                fileOnMaster:\n                  privateKeyFile: "/run/secrets/ec2-key.pem"\n'
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
  -e EC2_DEV_HOST= -e EC2_STAGE_HOST= -e EC2_PROD_HOST= \
  -v "$DIR/casc.yaml:/etc/jenkins/casc.yaml:ro" -v "$DIR/casc.d:/etc/jenkins/casc.d:ro" \
  "$image" >/dev/null
verdict=timeout
for _ in $(seq 1 40); do
  logs="$(docker logs "$probe" 2>&1 || true)"
  if grep -qE 'ConfiguratorException|Failed ConfigurationAsCode.init|BootFailure' <<<"$logs"; then verdict=invalid; break; fi
  if grep -q 'Jenkins is fully up and running' <<<"$logs"; then verdict=valid; break; fi
  sleep 5
done
if [[ "$verdict" != valid ]]; then
  echo "ERROR: pre-flight verdict=$verdict; production Jenkins was NOT touched. Relevant log lines:" >&2
  docker logs "$probe" 2>&1 | grep -E 'Exception|SEVERE|Available attributes|Caused' | cut -c1-300 | head -n 25 >&2 || true
  docker rm -f "$probe" >/dev/null 2>&1 || true
  exit 1
fi
docker rm -f "$probe" >/dev/null 2>&1 || true
echo 'Pre-flight OK.'

# JCasC reads credentials only at boot and they live in bind-mounted files, so Compose would not
# notice a change: recreate the controller (the volume keeps all data) only when they changed.
cred_hash="$(cat "$SECRETS" "$CASC_CREDS" "$ENVFILE" 2>/dev/null | sha256sum | cut -d' ' -f1)"
recreate=()
if [[ "$(cat "$DIR/.cred.hash" 2>/dev/null || true)" != "$cred_hash" ]]; then
  echo 'Credentials or CI environment changed: recreating the controller'
  recreate=(--force-recreate)
fi
"${COMPOSE[@]}" up -d "${recreate[@]}" jenkins
printf '%s\n' "$cred_hash" > "$DIR/.cred.hash"
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
