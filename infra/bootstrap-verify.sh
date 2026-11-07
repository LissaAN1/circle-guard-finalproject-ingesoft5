#!/usr/bin/env bash
# HU-01: read-only remote health verification; no credentials displayed.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap-common.sh
source "$HERE/bootstrap-common.sh"
bootstrap_require

for role in jenkins sonarqube nexus; do
  bootstrap_target "$role"
  printf '\n[%s] EC2 available; checking localhost service...\n' "$role"
  case "$role" in
    jenkins)
      bootstrap_ssh 'sudo docker inspect -f "{{.State.Health.Status}}" circleguard-jenkins'
      bootstrap_ssh 'curl -fsS -o /dev/null http://127.0.0.1:8080/login'
      ;;
    sonarqube)
      bootstrap_ssh 'sudo docker ps --filter name=circleguard-sonarqube --format "{{.Names}} {{.Status}}"'
      bootstrap_ssh "curl -fsS http://127.0.0.1:9000/api/system/status | grep -q '\"UP\"'"
      ;;
    nexus)
      bootstrap_ssh 'sudo docker ps --filter name=circleguard-nexus --format "{{.Names}} {{.Status}}"'
      bootstrap_ssh 'curl -fsS -o /dev/null http://127.0.0.1:8081/'
      bootstrap_ssh 'code=$(curl -sS -o /dev/null -w "%{http_code}" http://127.0.0.1:8082/v2/); echo "Docker Registry HTTP status: $code"; [[ "$code" == "401" || "$code" == "200" ]]'
      ;;
  esac
  printf '[%s] local service checks completed\n' "$role"
done
printf '\nRemote service checks completed. Confirm user login and remote network reachability separately.\n'
