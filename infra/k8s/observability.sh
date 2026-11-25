#!/usr/bin/env bash
# Deploy the observability stack into the namespace of one environment:
#   HU-17: Prometheus + Alertmanager    HU-18: Loki + Promtail + Grafana
#   ALERT_WEBHOOK_URL=https://... bash infra/k8s/observability.sh dev|stage|prod
# KUBE_CONTEXT selects the cluster (same rules as deploy.sh). Without ALERT_WEBHOOK_URL
# the alerts are still evaluated and visible in Alertmanager, but nothing is delivered.
# The webhook URL travels in a 0600 file inside a private temporary directory, never as an
# argument, and is removed on exit. The Grafana admin password (HU-18) is generated on the
# first run into the Secret grafana-admin, the same way: never in the repo, never as an argument.
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
# HU-18: loki.yaml, promtail.yaml and grafana.yaml are applied the same way.
for f in prometheus.yaml alertmanager.yaml loki.yaml promtail.yaml grafana.yaml; do
  sed "s#__NAMESPACE__#$ns#g" "$HERE/observability/$f" > "$work/$f"
done
cp "$REPO/observability/prometheus/prometheus.k8s.yml" "$work/prometheus.yml"
cp "$REPO/observability/alertmanager/alertmanager.yml" "$work/alertmanager.yml"
rules=()
for f in "$REPO"/observability/prometheus/rules/*.rules.yml; do
  cp "$f" "$work/$(basename "$f")"; rules+=("$(basename "$f")")
done

# HU-18: Loki, Promtail and Grafana settings, and the versioned dashboards.
cp "$REPO/observability/loki/loki-config.yaml" "$work/loki-config.yaml"
cp "$REPO/observability/loki/promtail-config.yaml" "$work/promtail-config.yaml"
cp "$REPO/observability/grafana/provisioning/datasources/datasources.yaml" "$work/datasources.yaml"
cp "$REPO/observability/grafana/provisioning/dashboards/dashboards.yaml" "$work/dashboards.yaml"
dashboards=()
for f in "$REPO"/observability/grafana/dashboards/*.json; do
  cp "$f" "$work/$(basename "$f")"; dashboards+=("$(basename "$f")")
done

{
  echo 'apiVersion: kustomize.config.k8s.io/v1beta1'
  echo 'kind: Kustomization'
  echo "namespace: $ns"
  echo 'resources: [prometheus.yaml, alertmanager.yaml, loki.yaml, promtail.yaml, grafana.yaml]'
  echo 'configMapGenerator:'
  echo '  - {name: prometheus-config, files: [prometheus.yml]}'
  printf '  - {name: prometheus-rules, files: [%s]}\n' "$(IFS=,; echo "${rules[*]}")"
  echo '  - {name: alertmanager-config, files: [alertmanager.yml]}'
  echo '  - {name: loki-config, files: [loki-config.yaml]}'
  echo '  - {name: promtail-config, files: [promtail-config.yaml]}'
  echo '  - {name: grafana-datasources, files: [datasources.yaml]}'
  echo '  - {name: grafana-dashboard-provider, files: [dashboards.yaml]}'
  printf '  - {name: grafana-dashboards, files: [%s]}\n' "$(IFS=,; echo "${dashboards[*]}")"
} > "$work/kustomization.yaml"

if [[ -z "${ALERT_WEBHOOK_URL:-}" ]]; then
  echo "ALERT_WEBHOOK_URL is not set: alerts will only be visible in Alertmanager (no delivery)." >&2
fi
printf '%s' "${ALERT_WEBHOOK_URL:-http://localhost:9/none}" > "$work/secret/webhook_url"

kc create namespace "$ns" --dry-run=client -o yaml | kc apply -f - >/dev/null
kc -n "$ns" create secret generic alertmanager-webhook --from-file=webhook_url="$work/secret/webhook_url" \
  --dry-run=client -o yaml | kc apply -f - >/dev/null

# HU-18: the Grafana admin Secret is created once (random password) and never overwritten.
if ! kc -n "$ns" get secret grafana-admin >/dev/null 2>&1; then
  printf 'admin' > "$work/secret/admin-user"
  openssl rand -base64 18 | tr -d '\n' > "$work/secret/admin-password"
  kc -n "$ns" create secret generic grafana-admin \
    --from-file=admin-user="$work/secret/admin-user" \
    --from-file=admin-password="$work/secret/admin-password" >/dev/null
fi

kc apply -k "$work"
kc -n "$ns" rollout status deployment/prometheus --timeout=300s
kc -n "$ns" rollout status deployment/alertmanager --timeout=300s
kc -n "$ns" rollout status deployment/loki --timeout=300s
kc -n "$ns" rollout status deployment/grafana --timeout=300s
kc -n "$ns" rollout status daemonset/promtail --timeout=300s
echo "Prometheus and Alertmanager are ready in $ns (kubectl --context $KUBE_CONTEXT -n $ns port-forward svc/prometheus 9090)"
echo "Loki, Promtail and Grafana are ready in $ns (kubectl --context $KUBE_CONTEXT -n $ns port-forward svc/grafana 3000:3000)"
