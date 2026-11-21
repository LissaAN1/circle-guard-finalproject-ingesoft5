# Shared helpers of the fault-injection scripts (sourced, not executed).
# Requires infra/k8s/lib.sh for select_cluster and kc (the cluster is pinned explicitly).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../infra/k8s/lib.sh
source "$HERE/../../infra/k8s/lib.sh"
ENVIRONMENT=${ENVIRONMENT:-dev}
NS="circleguard-$ENVIRONMENT"
select_cluster "$ENVIRONMENT"

# alert_active <alertname> [label=value]  -> exit 0 if Alertmanager has that alert firing
alert_active() {
  kc -n "$NS" exec deploy/alertmanager -- wget -qO- http://localhost:9093/api/v2/alerts 2>/dev/null |
  python3 -c '
import json, sys
name = sys.argv[1]; want = dict(a.split("=", 1) for a in sys.argv[2:])
alerts = json.load(sys.stdin)
ok = any(a["labels"].get("alertname") == name and a["status"]["state"] == "active"
         and all(a["labels"].get(k) == v for k, v in want.items()) for a in alerts)
sys.exit(0 if ok else 1)' "$@"
}

# wait_alert <timeout_s> <alertname> [label=value]
wait_alert() {
  local timeout="$1"; shift
  local end=$(( $(date +%s) + timeout ))
  while (( $(date +%s) < end )); do
    if alert_active "$@"; then echo "[$(date -Is)] ALERT $* ACTIVE"; return 0; fi
    sleep 10
  done
  echo "[$(date -Is)] ALERT $* DID NOT FIRE within ${timeout}s" >&2
  return 1
}
