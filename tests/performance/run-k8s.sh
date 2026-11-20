#!/usr/bin/env bash
# HU-21: run the Locust scenarios headless against the web Service of a Kubernetes
# environment and compare the result with targets.json. A missed target exits nonzero.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
env_name="${1:-}"
case "$env_name" in dev|stage) ;; *) echo 'Usage: run-k8s.sh dev|stage' >&2; exit 2;; esac
: "${KUBECONFIG:?Kubernetes kubeconfig is required}"
: "${E2E_USERNAME:?E2E survey account is required}"
: "${E2E_PASSWORD:?E2E survey password is required}"
cd "$ROOT"
export PATH="$ROOT/ci/scripts:$PATH"
KUBE_CONTEXT="circleguard-$env_name"; export KUBE_CONTEXT
source infra/k8s/lib.sh
select_cluster "$env_name"
ns="circleguard-$env_name"
case "$env_name" in dev) port=8782;; stage) port=8783;; esac
base="http://127.0.0.1:$port"
read -r users rate duration < <(jq -r '.load | "\(.users) \(.spawn_rate) \(.duration)"' tests/performance/targets.json)
out=ci/reports/performance
rm -rf "$out"; mkdir -p "$out"
AGENT_CONTAINER="${CG_AGENT_CONTAINER:-circleguard-build-agent}"
docker inspect "$AGENT_CONTAINER" >/dev/null
pf_log="$(mktemp)"; pf_pid=''
cleanup() { [[ -z "$pf_pid" ]] || kill "$pf_pid" 2>/dev/null || true; rm -f "$pf_log"; }
trap cleanup EXIT
kc -n "$ns" port-forward service/web "$port:80" --address 127.0.0.1 >"$pf_log" 2>&1 &
pf_pid=$!
ready=false
for _ in $(seq 1 30); do
  if curl -fsS --max-time 2 "$base/" >/dev/null 2>&1; then ready=true; break; fi
  kill -0 "$pf_pid" 2>/dev/null || break
  sleep 2
done
[[ "$ready" == true ]] || { echo "web port-forward failed ($env_name)" >&2; cat "$pf_log" >&2; exit 1; }
image="${CG_LOCUST_IMAGE:-locustio/locust:2.32.4}"
# Locust exits 1 when any request failed; the targets decide the verdict, so keep going.
set +e
DOPTS=(--rm --network "container:$AGENT_CONTAINER" --volumes-from "$AGENT_CONTAINER"
  --user "$(id -u):$(id -g)" -e HOME=/tmp -w "$ROOT")
docker run "${DOPTS[@]}" -e E2E_USERNAME -e E2E_PASSWORD -e CG_LOCUST_SEED=21 \
  "$image" -f tests/performance/locustfile.py --headless \
  --host "$base" -u "$users" -r "$rate" -t "$duration" --stop-timeout 10 \
  --csv "$out/locust" --html "$out/locust.html" --only-summary
locust_rc=$?
set -e
[[ -s "$out/locust_stats.csv" ]] || { echo "Locust produced no statistics (exit $locust_rc)" >&2; exit 1; }
# The agent has no Python; the Locust image does.
docker run "${DOPTS[@]}" --entrypoint python3 "$image" tests/performance/evaluate.py "$out/locust_stats.csv" tests/performance/targets.json "$out"
