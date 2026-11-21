#!/usr/bin/env bash
# Shared HPA control helpers for fault-injection scripts (sourced, not executed).

require_dev_env() {
  if [[ "${ENVIRONMENT:-}" != "dev" ]]; then
    echo "Error: fault injection is only permitted in the 'dev' environment (current: '${ENVIRONMENT:-}')." >&2
    exit 1
  fi
}

suspend_hpa() {
  local service="$1"
  local backup_file="$2"
  local hpa_name

  hpa_name="$(kc -n "$NS" get hpa "$service" --ignore-not-found -o name 2>/dev/null || true)"
  if [[ -n "$hpa_name" ]]; then
    echo "[$(date -Is)] Respaldando HPA de $service"
    # The saved object is re-created later: drop the fields the API server owns (uid, resourceVersion,
    # status...) or it rejects the create with "resourceVersion should not be set on objects to be created".
    if ! kc -n "$NS" get hpa "$service" -o json | python3 -c '
import json, sys
obj = json.load(sys.stdin)
meta = obj.get("metadata", {})
for key in ("uid", "resourceVersion", "generation", "creationTimestamp", "managedFields", "selfLink"):
    meta.pop(key, None)
obj.pop("status", None)
json.dump(obj, sys.stdout)
' > "$backup_file" || [[ ! -s "$backup_file" ]]; then
      echo "Error: no se pudo obtener un respaldo valido del HPA para $service" >&2
      exit 1
    fi
    echo "[$(date -Is)] Retirando temporalmente HPA de $service"
    if ! kc -n "$NS" delete hpa "$service" >/dev/null 2>&1; then
      echo "Error: no se pudo eliminar temporalmente el HPA para $service" >&2
      exit 1
    fi
    return 0
  fi
  return 1
}

restore_hpa() {
  local service="$1"
  local backup_file="$2"

  if [[ -f "$backup_file" && -s "$backup_file" ]]; then
    echo "[$(date -Is)] restaurando HPA de $service"
    if ! kc -n "$NS" apply -f "$backup_file" >/dev/null 2>&1; then
      echo "ERROR: fallo al restaurar HPA de $service" >&2
      return 1
    fi
  fi
  return 0
}
