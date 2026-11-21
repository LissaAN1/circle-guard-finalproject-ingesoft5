#!/usr/bin/env bash
# Prueba de HighErrorRate y CircuitBreakerOpen (HU-14): escala identity a 0 y hace logins validos contra
# auth. auth autentica contra LDAP y despues llama a identity: sin identity responde 503 (5xx) y, tras
# 5 fallos, abre el circuito. No afecta la salud de auth (HU-14 no registra el circuito en /actuator/health).
# Requiere una cuenta de prueba valida del LDAP en LOGIN_USER y LOGIN_PASSWORD (nunca en el repositorio).
# Uso: ENVIRONMENT=dev LOGIN_USER=... LOGIN_PASSWORD=... bash observability/scripts/fail-circuit-error-rate.sh
# Duracion aproximada: 5 a 8 minutos. ServiceDown tambien dispara para identity mientras esta en 0.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/alerts.sh"
: "${LOGIN_USER:?define LOGIN_USER}"; : "${LOGIN_PASSWORD:?define LOGIN_PASSWORD}"
replicas="$(kc -n "$NS" get deployment/identity -o jsonpath='{.spec.replicas}')"

umask 077
base="${XDG_RUNTIME_DIR:-}"; [[ -d "$base" && -w "$base" ]] || base="${TMPDIR:-/tmp}"
work="$(mktemp -d "$base/cg-fail.XXXXXX")"
cleanup() {
  echo "[$(date -Is)] limpiando y restaurando identity a $replicas replica(s)"
  kc -n "$NS" delete pod cg-load --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kc -n "$NS" delete secret cg-load-login --ignore-not-found >/dev/null 2>&1 || true
  kc -n "$NS" scale deployment/identity --replicas="$replicas" >/dev/null 2>&1 || true
  kc -n "$NS" rollout status deployment/identity --timeout=600s || true
  rm -rf "$work"
}
trap cleanup EXIT

printf '%s' "$LOGIN_USER" > "$work/user"; printf '%s' "$LOGIN_PASSWORD" > "$work/password"
kc -n "$NS" create secret generic cg-load-login --from-file=user="$work/user" --from-file=password="$work/password" >/dev/null

echo "[$(date -Is)] escalando identity a 0"
kc -n "$NS" scale deployment/identity --replicas=0
kc -n "$NS" apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: cg-load
  labels: {app: cg-load}
spec:
  restartPolicy: Never
  containers:
    - name: curl
      image: curlimages/curl:8.10.1
      env:
        - {name: LOGIN_USER, valueFrom: {secretKeyRef: {name: cg-load-login, key: user}}}
        - {name: LOGIN_PASSWORD, valueFrom: {secretKeyRef: {name: cg-load-login, key: password}}}
      command: [sh, -c]
      args:
        - |
          while true; do
            curl -s -o /dev/null -X POST http://auth:8180/api/v1/auth/login \
              -H 'Content-Type: application/json' \
              -d "{\"username\":\"$LOGIN_USER\",\"password\":\"$LOGIN_PASSWORD\"}"
            sleep 0.5
          done
YAML
kc -n "$NS" wait --for=condition=Ready pod/cg-load --timeout=180s

rc=0
wait_alert 480 CircuitBreakerOpen application=circleguard-auth-service || rc=1
wait_alert 300 HighErrorRate application=circleguard-auth-service || rc=1
exit $rc
