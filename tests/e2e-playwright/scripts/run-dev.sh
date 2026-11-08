#!/usr/bin/env bash
# CircleGuard HU-07: execute real E2E against the EXISTING DEV EC2.
# Runs inside the HU-04 build-agent, which mounts the Docker socket.
set -euo pipefail
: "${E2E_DEV_HOST:?Authorized DEV EC2 hostname/IP is required}"
: "${E2E_SSH_KEY:?Jenkins SSH key path is required}"
: "${E2E_SSH_USER:?SSH username is required}"
: "${E2E_USERNAME:?Dedicated survey account required}"
: "${E2E_PASSWORD:?Dedicated survey password required}"
: "${E2E_GATE_USERNAME:?Dedicated gate account required}"
: "${E2E_GATE_PASSWORD:?Dedicated gate password required}"
[[ "${E2E_DEDICATED_ACCOUNT_ACK:-}" == true ]] || { echo 'No authorization for DEV E2E fixture' >&2; exit 2; }
for program in ssh curl docker; do command -v "$program" >/dev/null || { echo "Missing $program in build-agent" >&2; exit 2; }; done
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"
AGENT_CONTAINER=circleguard-build-agent
if ! docker inspect "$AGENT_CONTAINER" >/dev/null 2>&1; then
  echo "Cannot inspect HU-04 agent container: $AGENT_CONTAINER" >&2; exit 1
fi
export E2E_BASE_URL=http://127.0.0.1:8780
SSH_OPTS=(-i "$E2E_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=yes -o ExitOnForwardFailure=yes -o ConnectTimeout=15)
SSH_PID=''
FIXTURE_PREPARED=false
GATE_UUID=''
PREVIOUS_STATUS=''
PREVIOUS_TTL=''
redis_dev() {
  local cmd="$1" uuid="$2" extra="${3:-}"
  ssh "${SSH_OPTS[@]}" "$E2E_SSH_USER@$E2E_DEV_HOST" \
    "sudo docker exec circleguard-dev-redis-1 sh -c 'REDISCLI_AUTH=\"\$REDIS_PASSWORD\" redis-cli --raw $cmd user:status:$uuid $extra'"
}
cleanup() {
  if [[ "$FIXTURE_PREPARED" == true ]]; then
    if [[ -z "$PREVIOUS_STATUS" ]]; then
      redis_dev DEL "$GATE_UUID" >/dev/null || echo 'WARNING: fixture cleanup failed; TTL=600s' >&2
    elif [[ "$PREVIOUS_TTL" =~ ^[1-9][0-9]*$ ]]; then
      redis_dev SET "$GATE_UUID" "$PREVIOUS_STATUS EX $PREVIOUS_TTL" >/dev/null || echo 'WARNING: fixture restore failed' >&2
    else
      redis_dev SET "$GATE_UUID" "$PREVIOUS_STATUS" >/dev/null || echo 'WARNING: fixture restore failed' >&2
    fi
  fi
  [[ -z "$SSH_PID" ]] || kill "$SSH_PID" 2>/dev/null || true
}
trap cleanup EXIT
ssh "${SSH_OPTS[@]}" -N -L 127.0.0.1:8780:127.0.0.1:80 \
  "$E2E_SSH_USER@$E2E_DEV_HOST" &
SSH_PID=$!
ready=false
for _ in $(seq 1 30); do
  if curl --fail --silent --show-error --max-time 2 "$E2E_BASE_URL/" >/dev/null 2>&1; then ready=true; break; fi
  if ! kill -0 "$SSH_PID" 2>/dev/null; then break; fi
  sleep 2
done
[[ "$ready" == true ]] || { echo 'Existing DEV frontend/tunnel unavailable; do not start EC2 automatically' >&2; exit 1; }
IMAGE=mcr.microsoft.com/playwright:v1.65.0-noble
DOPTS=(--rm --network "container:$AGENT_CONTAINER" --volumes-from "$AGENT_CONTAINER" \
  --user "$(id -u):$(id -g)" -e HOME=/tmp -e CI=true \
  -e E2E_BASE_URL -e E2E_USERNAME -e E2E_PASSWORD \
  -e E2E_GATE_USERNAME -e E2E_GATE_PASSWORD \
  -w "$ROOT/tests/e2e-playwright")
GATE_UUID="$(docker run "${DOPTS[@]}" "$IMAGE" node scripts/fixture-gate-user.mjs)"
[[ "$GATE_UUID" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo 'Invalid dedicated gate UUID' >&2; exit 1; }
PREVIOUS_STATUS="$(redis_dev GET "$GATE_UUID" | tr -d '\r')"
PREVIOUS_TTL="$(redis_dev TTL "$GATE_UUID" | tr -d '\r')"
if [[ -n "$PREVIOUS_STATUS" && "$PREVIOUS_STATUS" != ACTIVE ]]; then
  echo 'Gate fixture is not ACTIVE/empty; refusing to overwrite existing health status' >&2
  exit 1
fi
redis_dev SET "$GATE_UUID" 'CONFIRMED EX 600' | grep -qx OK || { echo 'Unable to seed test-only CONFIRMED in DEV' >&2; exit 1; }
FIXTURE_PREPARED=true
docker run "${DOPTS[@]}" "$IMAGE" sh -ec 'npm ci && npx playwright test'
