#!/usr/bin/env bash
# HU-21: OWASP ZAP baseline (passive scan, no attacks) against the web Service of a
# Kubernetes environment. Reports land in ci/reports/zap. Exit codes of zap-baseline.py:
# 0 clean, 2 warnings only (published, not blocking), 1 a FAIL rule hit, 3 scanner error.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
env_name="${1:-}"
case "$env_name" in dev|stage) ;; *) echo 'Usage: zap-run.sh dev|stage' >&2; exit 2;; esac
: "${KUBECONFIG:?Kubernetes kubeconfig is required}"
cd "$ROOT"
export PATH="$ROOT/ci/scripts:$PATH"
KUBE_CONTEXT="circleguard-$env_name"; export KUBE_CONTEXT
source infra/k8s/lib.sh
select_cluster "$env_name"
ns="circleguard-$env_name"
case "$env_name" in dev) port=8784;; stage) port=8785;; esac
target="http://127.0.0.1:$port/"
out=ci/reports/zap
rm -rf "$out"; mkdir -p "$out"
AGENT_CONTAINER="${CG_AGENT_CONTAINER:-circleguard-build-agent}"
docker inspect "$AGENT_CONTAINER" >/dev/null
image="${CG_ZAP_IMAGE:-zaproxy/zap-stable:2.16.0}"
name="cg-zap-${env_name}-${BUILD_NUMBER:-local}-$$"
pf_log="$(mktemp)"; pf_pid=''
cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  [[ -z "$pf_pid" ]] || kill "$pf_pid" 2>/dev/null || true
  rm -f "$pf_log"
}
trap cleanup EXIT
kc -n "$ns" port-forward service/web "$port:80" --address 127.0.0.1 >"$pf_log" 2>&1 &
pf_pid=$!
ready=false
for _ in $(seq 1 30); do
  if curl -fsS --max-time 2 "$target" >/dev/null 2>&1; then ready=true; break; fi
  kill -0 "$pf_pid" 2>/dev/null || break
  sleep 2
done
[[ "$ready" == true ]] || { echo "web port-forward failed ($env_name)" >&2; cat "$pf_log" >&2; exit 1; }
# The agent runs Docker through the host socket, so bind mounts would resolve on the
# host. The rules go in and the reports come out with docker cp instead; docker cp
# creates /zap/wrk owned by root, so the throwaway scan container runs as root.
docker create --name "$name" --user root --network "container:$AGENT_CONTAINER" "$image" \
  zap-baseline.py -t "$target" -c rules.tsv -m 3 -T 10 \
  -r zap-report.html -J zap-report.json -w zap-report.md >/dev/null
docker cp ci/zap/. "$name:/zap/wrk"
set +e
docker start -a "$name"
rc=$?
set -e
docker cp "$name:/zap/wrk/." "$out" || true
[[ -s "$out/zap-report.html" ]] || { echo "ZAP produced no report (exit $rc)" >&2; exit 1; }
case "$rc" in
  0) echo "ZAP baseline: no alerts above the configured threshold";;
  2) echo "ZAP baseline: warnings only; see the published report";;
  1) echo "ZAP baseline: a FAIL rule was hit; promotion blocked" >&2; exit 1;;
  *) echo "ZAP baseline: scanner error (exit $rc)" >&2; exit 1;;
esac
