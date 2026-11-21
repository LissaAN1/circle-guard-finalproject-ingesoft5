#!/usr/bin/env bash
# HU-23: prove the three acceptance criteria in dev.   bash infra/mesh/verify.sh
#  1. every CircleGuard Deployment has the linkerd-proxy container;
#  2. a client without mesh identity (no mTLS) is rejected, one with the proxy gets the answer;
#  3. the canary splits the traffic between hello-v1 and hello-v2.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../k8s/lib.sh"
select_cluster dev
NS=circleguard-dev; DEMO=mesh-demo
trap 'kc -n $DEMO delete pod client-meshed client-plain --ignore-not-found --wait=false >/dev/null 2>&1 || true' EXIT

echo "== 1. proxy injected in the CircleGuard Deployments"
# Linkerd injects the proxy as a native sidecar (an init container that keeps running).
kc -n "$NS" get pods -o custom-columns='POD:.metadata.name,APP:.spec.containers[*].name,SIDECAR:.spec.initContainers[*].name' --no-headers |
  awk '$1 ~ /^(auth|dashboard|file|form|gateway|identity|notification|promotion|web)-/ {print ($3 ~ /linkerd-proxy/ ? "  meshed   " : "  NO MESH  ") $1 "  [" $2 " + " $3 "]"}'

kc -n "$DEMO" delete pod client-meshed client-plain --ignore-not-found --wait=true >/dev/null 2>&1 || true
echo "== 2. strict mTLS (default inbound policy all-authenticated)"
kc -n "$DEMO" run client-meshed --image=curlimages/curl:8.10.1 --restart=Never --command -- sleep 600 >/dev/null
kc -n "$DEMO" run client-plain --image=curlimages/curl:8.10.1 --restart=Never --overrides='{"metadata":{"annotations":{"linkerd.io/inject":"disabled"}}}' --command -- sleep 600 >/dev/null
kc -n "$DEMO" wait --for=condition=Ready pod/client-meshed pod/client-plain --timeout=240s >/dev/null 2>&1
echo "  with mesh identity    : $(kc -n $DEMO exec client-meshed -c client-meshed -- curl -s -m 8 http://hello-v1/ || echo FAILED)"
if out=$(kc -n "$DEMO" exec client-plain -- curl -s -m 8 -o /dev/null -w '%{http_code}' http://hello-v1/ 2>&1); then
  [[ "$out" == "200" ]] && { echo "  without mTLS (plain)  : ANSWERED (not rejected)" >&2; exit 1; }
  echo "  without mTLS (plain)  : REJECTED by the proxy (HTTP $out)"
else echo "  without mTLS (plain)  : REJECTED (curl failed: $out)"; fi

echo "== 3. canary 90/10 over 100 requests"
kc -n "$DEMO" exec client-meshed -c client-meshed -- sh -c 'for i in $(seq 1 100); do curl -s -m 5 http://hello/; done' |
  grep -v '^$' | sort | uniq -c | sort -rn
