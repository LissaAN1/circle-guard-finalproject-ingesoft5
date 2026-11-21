#!/usr/bin/env bash
# Deploy Prometheus and Alertmanager (HU-17) into the namespace of one environment:
#   ALERT_WEBHOOK_URL=https://... bash infra/k8s/observability.sh dev|stage|prod
# KUBE_CONTEXT selects the cluster (same rules as deploy.sh). Without ALERT_WEBHOOK_URL
# the alerts are still evaluated and visible in Alertmanager, but nothing is delivered.
# The webhook URL travels in a 0600 file inside a private temporary directory, never as an
# argument, and is removed on exit.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
env="${1:-}"
case "$env" in dev|stage|prod) ;; *) echo 'Usage: observability.sh dev|stage|prod' >&2; exit 2 ;; esac
select_cluster "$env"
ns="circleguard-$env"

umask 077
base="${XDG_RUNTIME_DIR:-}"
[[ -d "$base" && -w "$base" ]] || base="${TMPDIR:-/tmp}"
work="$(mktemp -d "$base/cg-obs.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir "$work/secret"

# The rules, Prometheus and Alertmanager settings live once under observability/.
for f in prometheus.yaml alertmanager.yaml; do
  sed "s#__NAMESPACE__#$ns#g" "$HERE/observability/$f" > "$work/$f"
done
cp "$REPO/observability/prometheus/prometheus.k8s.yml" "$work/prometheus.yml"
cp "$REPO/observability/alertmanager/alertmanager.yml" "$work/alertmanager.yml"
rules=()
for f in "$REPO"/observability/prometheus/rules/*.rules.yml; do
  cp "$f" "$work/$(basename "$f")"; rules+=("$(basename "$f")")
done
{
  echo 'apiVersion: kustomize.config.k8s.io/v1beta1'
  echo 'kind: Kustomization'
  echo "namespace: $ns"
  echo 'resources: [prometheus.yaml, alertmanager.yaml]'
  echo 'configMapGenerator:'
  echo '  - {name: prometheus-config, files: [prometheus.yml]}'
  printf '  - {name: prometheus-rules, files: [%s]}\n' "$(IFS=,; echo "${rules[*]}")"
  echo '  - {name: alertmanager-config, files: [alertmanager.yml]}'
} > "$work/kustomization.yaml"

if [[ -z "${ALERT_WEBHOOK_URL:-}" ]]; then
  echo "ALERT_WEBHOOK_URL is not set: alerts will only be visible in Alertmanager (no delivery)." >&2
fi
printf '%s' "${ALERT_WEBHOOK_URL:-http://localhost:9/none}" > "$work/secret/webhook_url"

kc create namespace "$ns" --dry-run=client -o yaml | kc apply -f - >/dev/null
kc -n "$ns" create secret generic alertmanager-webhook --from-file=webhook_url="$work/secret/webhook_url" \
  --dry-run=client -o yaml | kc apply -f - >/dev/null
kc apply -k "$work"
kc -n "$ns" rollout status deployment/prometheus --timeout=300s
kc -n "$ns" rollout status deployment/alertmanager --timeout=300s
echo "Prometheus and Alertmanager are ready in $ns (kubectl --context $KUBE_CONTEXT -n $ns port-forward svc/prometheus 9090)"
