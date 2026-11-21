#!/usr/bin/env bash
# Prueba de ServiceDown: escala un Deployment a 0, espera la alerta y restaura las replicas.
# Uso: ENVIRONMENT=dev SERVICE=auth bash observability/scripts/fail-service-down.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/alerts.sh"
source "$HERE/hpa-control.sh"

SERVICE=${SERVICE:-auth}

require_dev_env

replicas="$(kc -n "$NS" get "deployment/$SERVICE" -o jsonpath='{.spec.replicas}')"

umask 077
base="${XDG_RUNTIME_DIR:-}"; [[ -d "$base" && -w "$base" ]] || base="${TMPDIR:-/tmp}"
work="$(mktemp -d "$base/cg-fail-sd.XXXXXX")"
hpa_backup="$work/hpa-$SERVICE.yaml"
hpa_altered=0

restore() {
  local exit_code=$?
  local restore_failed=0
  echo "[$(date -Is)] restaurando $SERVICE a $replicas replica(s)"

  if [[ "$hpa_altered" -eq 1 ]]; then
    if ! restore_hpa "$SERVICE" "$hpa_backup"; then
      restore_failed=1
    fi
  fi

  if [[ -n "${replicas:-}" ]]; then
    if ! kc -n "$NS" scale "deployment/$SERVICE" --replicas="$replicas"; then
      echo "ERROR: fallo al escalar $SERVICE a $replicas" >&2
      restore_failed=1
    fi
    if ! kc -n "$NS" rollout status "deployment/$SERVICE" --timeout=600s; then
      echo "ERROR: fallo en rollout status de $SERVICE" >&2
      restore_failed=1
    fi
  fi

  rm -rf "$work"

  if [[ "$restore_failed" -ne 0 ]]; then
    echo "ERROR: la restauracion de recursos no se completo con exito" >&2
    exit 1
  fi
  exit "$exit_code"
}
trap restore EXIT

if suspend_hpa "$SERVICE" "$hpa_backup"; then
  hpa_altered=1
fi

echo "[$(date -Is)] escalando $SERVICE a 0"
kc -n "$NS" scale "deployment/$SERVICE" --replicas=0
wait_alert "${WAIT_TIMEOUT:-300}" ServiceDown "service=$SERVICE"
