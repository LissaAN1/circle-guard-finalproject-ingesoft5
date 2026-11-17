#!/usr/bin/env bash
# Deploy one environment: bash infra/k8s/deploy.sh dev|stage|prod <registry> <version>
# Registry and version are arguments so no environment data lives in the repository.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env="${1:-}"; registry="${2:-}"; version="${3:-}"
case "$env" in dev|stage|prod) ;; *) echo 'Usage: deploy.sh dev|stage|prod <registry> <version>' >&2; exit 2 ;; esac
[[ -n "$registry" && -n "$version" ]] || { echo 'registry and version are required' >&2; exit 2; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cp -r "$HERE/base" "$HERE/overlays" "$work/"
for svc in auth identity promotion form gateway dashboard file notification; do
  sed -i "s#image: circleguard-${svc}-service\$#image: ${registry}/circleguard/circleguard-${svc}-service:${version}#" "$work/base/apps/${svc}.yaml"
done
sed -i "s#image: circleguard-web\$#image: ${registry}/circleguard/circleguard-web:${version}#" "$work/base/apps/web.yaml"
cd "$work/overlays/$env"
kubectl apply -k .
kubectl -n "circleguard-$env" rollout status statefulset --timeout=600s
kubectl -n "circleguard-$env" rollout status deployment --timeout=600s
