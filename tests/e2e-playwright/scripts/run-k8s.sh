#!/usr/bin/env bash
# Run the existing Playwright scenarios against a Kubernetes web Service.
# The dedicated gate fixture is prepared in the same environment's Redis pod.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
env_name="${1:-}"
case "$env_name" in dev|stage) ;; *) echo 'Usage: run-k8s.sh dev|stage' >&2; exit 2;; esac
: "${KUBECONFIG:?Kubernetes kubeconfig is required}"
: "${E2E_USERNAME:?E2E survey account is required}"
: "${E2E_PASSWORD:?E2E survey password is required}"
: "${E2E_GATE_USERNAME:?E2E gate account is required}"
: "${E2E_GATE_PASSWORD:?E2E gate password is required}"
[[ "${E2E_DEDICATED_ACCOUNT_ACK:-}" == true ]] || exit 2
cd "$ROOT"
export PATH="$ROOT/ci/scripts:$PATH"
KUBE_CONTEXT="circleguard-$env_name"; export KUBE_CONTEXT
# Verify a separate context exists before touching the namespace.
source infra/k8s/lib.sh
select_cluster "$env_name"
ns="circleguard-$env_name"
case "$env_name" in dev) port=8780;; stage) port=8781;; esac
export E2E_BASE_URL="http://127.0.0.1:$port"
AGENT_CONTAINER="${CG_AGENT_CONTAINER:-circleguard-build-agent}"
docker inspect "$AGENT_CONTAINER" >/dev/null
pf_log="$(mktemp)"
pf_pid=''; prepared=false; gate_uuid=''; previous_status=''; previous_ttl=''
redis_cmd() {
  local command="$1" uuid="$2"; shift 2
  [[ "$uuid" =~ ^[0-9a-fA-F-]{36}$ ]] || return 2
  case "$command" in GET|TTL|DEL|SET) ;; *) return 2;; esac
  kc -n "$ns" exec statefulset/redis -- sh -c \
    'export REDISCLI_AUTH="$REDIS_PASSWORD"; exec redis-cli --raw "$@"' \
    sh "$command" "user:status:$uuid" "$@"
}
cleanup() {
  if [[ "$prepared" == true ]]; then
    if [[ -z "$previous_status" ]]; then
      redis_cmd DEL "$gate_uuid" >/dev/null || true
    elif [[ "$previous_ttl" =~ ^[1-9][0-9]*$ ]]; then
      redis_cmd SET "$gate_uuid" "$previous_status" EX "$previous_ttl" >/dev/null || true
    else
      redis_cmd SET "$gate_uuid" "$previous_status" >/dev/null || true
    fi
  fi
  [[ -z "$pf_pid" ]] || kill "$pf_pid" 2>/dev/null || true
  rm -f "$pf_log"
}
trap cleanup EXIT
kc -n "$ns" port-forward service/web "$port:80" --address 127.0.0.1 >"$pf_log" 2>&1 &
pf_pid=$!
ready=false
for _ in $(seq 1 30); do
  if curl -fsS --max-time 2 "$E2E_BASE_URL/" >/dev/null 2>&1; then ready=true; break; fi
  kill -0 "$pf_pid" 2>/dev/null || break
  sleep 2
done
[[ "$ready" == true ]] || { echo "web port-forward failed ($env_name)" >&2; cat "$pf_log" >&2; exit 1; }
IMAGE=mcr.microsoft.com/playwright:v1.65.0-noble
DOPTS=(--rm --network "container:$AGENT_CONTAINER" --volumes-from "$AGENT_CONTAINER"
  --user "$(id -u):$(id -g)" -e HOME=/tmp -e CI=true -e E2E_BASE_URL
  -e E2E_USERNAME -e E2E_PASSWORD -e E2E_GATE_USERNAME -e E2E_GATE_PASSWORD
  -w "$ROOT/tests/e2e-playwright")
gate_uuid="$(docker run "${DOPTS[@]}" "$IMAGE" node scripts/fixture-gate-user.mjs)"
[[ "$gate_uuid" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo 'Invalid E2E fixture UUID' >&2; exit 1; }
previous_status="$(redis_cmd GET "$gate_uuid" | tr -d '\r')"
previous_ttl="$(redis_cmd TTL "$gate_uuid" | tr -d '\r')"
[[ -z "$previous_status" || "$previous_status" == ACTIVE ]] || { echo 'Existing gate state is not safe to overwrite' >&2; exit 1; }
redis_cmd SET "$gate_uuid" CONFIRMED EX 600 | grep -qx OK
prepared=true
docker run "${DOPTS[@]}" "$IMAGE" sh -ec 'npm ci && npx playwright test'
