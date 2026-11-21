#!/usr/bin/env bash
# Prueba de ServiceDown: escala un Deployment a 0, espera la alerta y restaura las replicas.
# Uso: ENVIRONMENT=dev SERVICE=auth bash observability/scripts/fail-service-down.sh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/alerts.sh"
SERVICE=${SERVICE:-auth}
replicas="$(kc -n "$NS" get "deployment/$SERVICE" -o jsonpath='{.spec.replicas}')"
restore() {
  echo "[$(date -Is)] restaurando $SERVICE a $replicas replica(s)"
  kc -n "$NS" scale "deployment/$SERVICE" --replicas="$replicas"
  kc -n "$NS" rollout status "deployment/$SERVICE" --timeout=600s
}
trap restore EXIT
echo "[$(date -Is)] escalando $SERVICE a 0"
kc -n "$NS" scale "deployment/$SERVICE" --replicas=0
wait_alert 300 ServiceDown "service=$SERVICE"
