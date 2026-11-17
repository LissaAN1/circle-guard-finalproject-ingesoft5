#!/usr/bin/env bash
# Deploy one environment:
#   bash infra/k8s/deploy.sh dev|stage|prod <registry> <version>
# KUBE_CONTEXT (default circleguard-<env>) selects the cluster and must belong to
# the environment. Registry and version are arguments so nothing environment
# specific is committed. Exits non-zero as soon as a workload does not become
# ready, so a pipeline (HU-13) can stop the promotion.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
env="${1:-}"; registry="${2:-}"; version="${3:-}"
case "$env" in dev|stage|prod) ;; *) echo 'Usage: deploy.sh dev|stage|prod <registry> <version>' >&2; exit 2 ;; esac
[[ -n "$registry" && -n "$version" ]] || { echo 'registry and version are required' >&2; exit 2; }
select_cluster "$env"
ns="circleguard-$env"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cp -r "$HERE/base" "$HERE/overlays" "$work/"
for svc in auth identity promotion form gateway dashboard file notification; do
  sed -i "s#image: circleguard-${svc}-service\$#image: ${registry}/circleguard/circleguard-${svc}-service:${version}#" "$work/base/apps/${svc}.yaml"
done
sed -i "s#image: circleguard-web\$#image: ${registry}/circleguard/circleguard-web:${version}#" "$work/base/apps/web.yaml"

kc apply -k "$work/overlays/$env"

# Wait for every workload explicitly; set -e stops the script on the first failure.
for app in "${WORKLOAD_STATEFULSETS[@]}"; do
  kc -n "$ns" rollout status "statefulset/$app" --timeout=600s
done
for app in "${WORKLOAD_DEPLOYMENTS[@]}"; do
  kc -n "$ns" rollout status "deployment/$app" --timeout=600s
done
echo "All $((${#WORKLOAD_STATEFULSETS[@]} + ${#WORKLOAD_DEPLOYMENTS[@]})) workloads of $ns are ready"
