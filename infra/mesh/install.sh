#!/usr/bin/env bash
# HU-23: install Linkerd in the dev cluster only.   bash infra/mesh/install.sh
# KUBE_CONTEXT selects the cluster (same rules as the other infra/k8s scripts).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../k8s/lib.sh"
select_cluster dev
bash "$HERE/issue-certs.sh"
P="$HERE/.private"
kc apply -f - <<YAML >/dev/null
apiVersion: v1
kind: Namespace
metadata: {name: linkerd, annotations: {linkerd.io/inject: disabled}, labels: {linkerd.io/is-control-plane: "true", config.linkerd.io/admission-webhooks: disabled, pod-security.kubernetes.io/enforce: privileged}}
YAML
# The issuer key travels only in this Secret of the cluster, never in a manifest.
kc -n linkerd create secret generic linkerd-identity-issuer --type=kubernetes.io/tls \
  --from-file=tls.crt="$P/issuer.crt" --from-file=tls.key="$P/issuer.key" --from-file=ca.crt="$P/ca.crt" \
  --dry-run=client -o yaml | kc apply -f - >/dev/null
python3 - "$HERE/linkerd.yaml" "$P/ca.crt" <<'PY' | kc apply -f -
import sys
manifest, anchor = open(sys.argv[1], encoding="utf-8").read(), open(sys.argv[2], encoding="utf-8").read()
print(manifest.replace("      __TRUST_ANCHOR__", chr(10).join("      " + l for l in anchor.splitlines())))
PY
echo "Waiting for the control plane..."
for i in $(seq 1 40); do
  n=$(kc -n linkerd get pods --no-headers 2>/dev/null | grep -c . || true)
  ready=$(kc -n linkerd get pods --no-headers 2>/dev/null | grep -c " 2/2 \| 1/1 " || true)
  [[ "$n" -ge 3 && "$n" -eq "$ready" ]] && break; sleep 10
done
kc -n linkerd get pods
