#!/usr/bin/env bash
# HU-22: ejecuta rollback de un Deployment o de todo el ambiente en Kubernetes.
# Uso:
#   bash infra/k8s/rollback.sh dev auth              # revierte solo auth a la revisión anterior
#   bash infra/k8s/rollback.sh dev auth 2            # revierte auth a la revisión 2
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

env="${1:-}"
service="${2:-}"
revision="${3:-}"

case "$env" in dev|stage|prod) ;; *) echo 'Uso: rollback.sh dev|stage|prod <servicio> [revision]' >&2; exit 2 ;; esac
[[ -n "$service" ]] || { echo 'Debe indicar el nombre del Deployment (ej. auth, promotion, web).' >&2; exit 2; }

select_cluster "$env"
ns="circleguard-$env"

echo "=== Historial antes del rollback ($ns/$service) ==="
kc -n "$ns" rollout history "deployment/$service"

if [[ -n "$revision" ]]; then
  kc -n "$ns" rollout undo "deployment/$service" --to-revision="$revision"
else
  kc -n "$ns" rollout undo "deployment/$service"
fi

kc -n "$ns" rollout status "deployment/$service" --timeout=300s

echo "=== Estado tras el rollback ($ns/$service) ==="
kc -n "$ns" rollout history "deployment/$service"
kc -n "$ns" get pods -l "app.kubernetes.io/name=$service" -o wide
