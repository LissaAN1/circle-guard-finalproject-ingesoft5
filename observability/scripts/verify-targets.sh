#!/usr/bin/env bash
# Criterio 1: los 8 servicios aparecen UP en Prometheus (todos sus pods). Solo lectura.
# Uso: kubectl --context circleguard-dev -n circleguard-dev port-forward svc/prometheus 9090 &
#      PROM_URL=http://127.0.0.1:9090 EXPECTED=8 bash observability/scripts/verify-targets.sh
set -euo pipefail
PROM_URL=${PROM_URL:-http://127.0.0.1:9090}
export EXPECTED=${EXPECTED:-8}
JSON="$(curl -fsS "$PROM_URL/api/v1/targets?state=active")" python3 - <<'PY'
import json, os, sys
expected = int(os.environ["EXPECTED"])
rows = [t for t in json.loads(os.environ["JSON"])["data"]["activeTargets"]
        if t["labels"].get("job") == "circleguard-services"]
services = {}
for t in sorted(rows, key=lambda t: (t["labels"].get("service", ""), t["labels"].get("pod", ""))):
    labels = t["labels"]
    services.setdefault(labels.get("service", "?"), []).append(t["health"] == "up")
    print(f'{labels.get("application", "?"):34} {labels.get("pod", "?"):40} {t["health"].upper()}')
healthy = [s for s, v in services.items() if v and all(v)]
print(f"Servicios con todos sus pods UP: {len(healthy)}/{expected}")
sys.exit(0 if len(healthy) == expected and len(services) == expected else 1)
PY
