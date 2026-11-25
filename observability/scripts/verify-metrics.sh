#!/usr/bin/env bash
# Criterio 2: existen las metricas de negocio (consulta a Prometheus). Solo lectura.
set -euo pipefail
PROM_URL=${PROM_URL:-http://127.0.0.1:9090}
q() { curl -fsS --get "$PROM_URL/api/v1/query" --data-urlencode "query=$1"; echo; }
echo "# promociones por minuto";     q 'sum(rate(circleguard_promotions_total[1m])) * 60'
echo "# promociones por estado";     q 'sum by (status) (circleguard_promotions_total)'
echo "# check-ins por resultado";    q 'sum by (result) (circleguard_checkins_total)'
echo "# contencion p95 (segundos)";  q 'histogram_quantile(0.95, sum by (le) (rate(circleguard_containment_duration_seconds_bucket[5m])))'
echo "# estado de los circuit breakers (HU-14)"; q 'resilience4j_circuitbreaker_state == 1'
