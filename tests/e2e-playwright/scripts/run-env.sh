#!/usr/bin/env bash
# CircleGuard HU-07: run E2E against an authorized DEV or STAGE EC2.
# Runs inside the HU-04 build-agent with access to the Docker socket.
set -euo pipefail

E2E_ENV="${1:-}"

case "$E2E_ENV" in
  dev|stage) ;;
  *)
    echo "Usage: run-env.sh dev|stage" >&2
    exit 2
    ;;
esac

: "${E2E_TARGET_HOST:?Authorized EC2 hostname/IP is required}"
: "${E2E_SSH_KEY:?Jenkins SSH key path is required}"
: "${E2E_SSH_USER:?SSH username is required}"
: "${E2E_USERNAME:?Dedicated survey account required}"
: "${E2E_PASSWORD:?Dedicated survey password required}"
: "${E2E_GATE_USERNAME:?Dedicated gate account required}"
: "${E2E_GATE_PASSWORD:?Dedicated gate password required}"

[[ "${E2E_DEDICATED_ACCOUNT_ACK:-}" == true ]] || {
  echo "No authorization for $E2E_ENV E2E fixture" >&2
  exit 2
}

for program in ssh curl docker; do
  command -v "$program" >/dev/null || {
    echo "Missing $program in build-agent" >&2
    exit 2
  }
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

AGENT_CONTAINER=circleguard-build-agent

if ! docker inspect "$AGENT_CONTAINER" >/dev/null 2>&1; then
  echo "Cannot inspect HU-04 agent container: $AGENT_CONTAINER" >&2
  exit 1
fi

# Use separate local ports to avoid mixing DEV and STAGE tunnels.
case "$E2E_ENV" in
  dev) E2E_LOCAL_PORT=8780 ;;
  stage) E2E_LOCAL_PORT=8781 ;;
esac

export E2E_BASE_URL="http://127.0.0.1:${E2E_LOCAL_PORT}"

SSH_OPTS=(
  -i "$E2E_SSH_KEY"
  -o BatchMode=yes
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=yes
  -o ExitOnForwardFailure=yes
  -o ConnectTimeout=15
)

SSH_TARGET="${E2E_SSH_USER}@${E2E_TARGET_HOST}"
REDIS_CONTAINER="circleguard-${E2E_ENV}-redis-1"

SSH_PID=''
FIXTURE_PREPARED=false
GATE_UUID=''
PREVIOUS_STATUS=''
PREVIOUS_TTL=''

redis_env() {
  local cmd="$1"
  local uuid="$2"
  local extra="${3:-}"

  [[ "$uuid" =~ ^[0-9a-fA-F-]{36}$ ]] || {
    echo "Invalid gate UUID" >&2
    return 2
  }

  case "$cmd" in
    GET|TTL|DEL|SET) ;;
    *)
      echo "Unsupported Redis fixture command" >&2
      return 2
      ;;
  esac

  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
    "sudo docker exec $REDIS_CONTAINER sh -c 'REDISCLI_AUTH=\"\$REDIS_PASSWORD\" redis-cli --raw $cmd user:status:$uuid $extra'"
}

cleanup() {
  if [[ "$FIXTURE_PREPARED" == true ]]; then
    if [[ -z "$PREVIOUS_STATUS" ]]; then
      redis_env DEL "$GATE_UUID" >/dev/null ||
        echo "WARNING: $E2E_ENV fixture cleanup failed; TTL=600s" >&2
    elif [[ "$PREVIOUS_TTL" =~ ^[1-9][0-9]*$ ]]; then
      redis_env SET "$GATE_UUID" "$PREVIOUS_STATUS EX $PREVIOUS_TTL" >/dev/null ||
        echo "WARNING: $E2E_ENV fixture restore failed" >&2
    else
      redis_env SET "$GATE_UUID" "$PREVIOUS_STATUS" >/dev/null ||
        echo "WARNING: $E2E_ENV fixture restore failed" >&2
    fi
  fi

  [[ -z "$SSH_PID" ]] || kill "$SSH_PID" 2>/dev/null || true
}

trap cleanup EXIT

echo "Starting authorized E2E validation for $E2E_ENV"

ssh "${SSH_OPTS[@]}" \
  -N \
  -L "127.0.0.1:${E2E_LOCAL_PORT}:127.0.0.1:80" \
  "$SSH_TARGET" &

SSH_PID=$!

ready=false

for _ in $(seq 1 30); do
  if curl --fail --silent --show-error --max-time 2 \
      "$E2E_BASE_URL/" >/dev/null 2>&1; then
    ready=true
    break
  fi

  if ! kill -0 "$SSH_PID" 2>/dev/null; then
    break
  fi

  sleep 2
done

[[ "$ready" == true ]] || {
  echo "$E2E_ENV frontend/tunnel unavailable; do not start EC2 automatically" >&2
  exit 1
}

IMAGE=mcr.microsoft.com/playwright:v1.65.0-noble

DOPTS=(
  --rm
  --network "container:$AGENT_CONTAINER"
  --volumes-from "$AGENT_CONTAINER"
  --user "$(id -u):$(id -g)"
  -e HOME=/tmp
  -e CI=true
  -e E2E_BASE_URL
  -e E2E_USERNAME
  -e E2E_PASSWORD
  -e E2E_GATE_USERNAME
  -e E2E_GATE_PASSWORD
  -w "$ROOT/tests/e2e-playwright"
)

GATE_UUID="$(
  docker run "${DOPTS[@]}" "$IMAGE" \
    node scripts/fixture-gate-user.mjs
)"

[[ "$GATE_UUID" =~ ^[0-9a-fA-F-]{36}$ ]] || {
  echo "Invalid dedicated gate UUID" >&2
  exit 1
}

PREVIOUS_STATUS="$(redis_env GET "$GATE_UUID" | tr -d '\r')"
PREVIOUS_TTL="$(redis_env TTL "$GATE_UUID" | tr -d '\r')"

if [[ -n "$PREVIOUS_STATUS" && "$PREVIOUS_STATUS" != ACTIVE ]]; then
  echo "Gate fixture is not ACTIVE/empty; refusing to overwrite existing health status" >&2
  exit 1
fi

redis_env SET "$GATE_UUID" 'CONFIRMED EX 600' | grep -qx OK || {
  echo "Unable to seed test-only CONFIRMED in $E2E_ENV" >&2
  exit 1
}

FIXTURE_PREPARED=true

docker run "${DOPTS[@]}" "$IMAGE" \
  sh -ec 'npm ci && npx playwright test'
