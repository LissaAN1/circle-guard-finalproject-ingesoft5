#!/usr/bin/env bash
# HU-24: run one Chaos Mesh experiment against dev and always remove it afterwards.
#   bash infra/chaos/run-experiment.sh infra/chaos/experiments/01-pod-kill-promotion.yaml
#   ALERT=ServiceDown ALERT_LABEL=service=identity WAIT_ALERT=240 \
#     bash infra/chaos/run-experiment.sh infra/chaos/experiments/02-pod-failure-identity.yaml
# Only dev is allowed (the chaos controller also ignores namespaces without chaos-mesh.org/inject=enabled).
# With ALERT set, the script waits until that alert is firing in Alertmanager (HU-17) and fails if it is not.
set -euo pipefail
file="${1:?usage: run-experiment.sh <experiment.yaml>}"
[[ -f "$file" ]] || { echo "no such file: $file" >&2; exit 2; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ENVIRONMENT=dev
if [[ -n "${ALERT:-}" ]]; then
  source "$HERE/../../observability/scripts/alerts.sh"     # select_cluster, kc, wait_alert
else
  source "$HERE/../k8s/lib.sh"; NS=circleguard-dev; select_cluster dev
fi
grep -q "namespace: circleguard-dev" "$file" || { echo "the experiment must target circleguard-dev" >&2; exit 2; }

kind_name="$(awk '/^kind:/{k=$2} /^  name:/{n=$2} END{print tolower(k) "/" n}' "$file")"
cleanup() { kc -n "$NS" delete "$kind_name" --ignore-not-found --wait=false >/dev/null 2>&1 || true; echo "[$(date -Is)] experiment removed"; }
trap cleanup EXIT

echo "[$(date -Is)] applying $file"
kc apply -f "$file"
rc=0
if [[ -n "${ALERT:-}" ]]; then
  # shellcheck disable=SC2086
  wait_alert "${WAIT_ALERT:-240}" "$ALERT" ${ALERT_LABEL:-} || rc=1
else
  sleep "${OBSERVE_SECONDS:-120}"
fi
kc -n "$NS" get pods --no-headers | awk '{print $1, $2, $3}'
exit $rc
