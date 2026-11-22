#!/usr/bin/env bash
# A cluster administrator runs this once per credential rotation on a trusted
# workstation. The generated kubeconfig has a short-lived namespace-scoped token.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
env_name="${1:-}"; admin_context="${2:-}"; api_server="${3:-}"; output="${4:-}"
access="${5:-deploy}"
case "$access" in
  deploy) service_account=jenkins-deployer; manifest=jenkins-deployer.yaml; credential="kubeconfig-$env_name" ;;
  e2e) service_account=jenkins-e2e; manifest=jenkins-e2e.yaml; credential="kubeconfig-e2e-$env_name" ;;
  *) echo 'Access must be deploy or e2e' >&2; exit 2 ;;
esac
case "$env_name" in dev|stage|prod) ;; *) echo 'Usage: provision-kubeconfig.sh dev|stage|prod ADMIN_CONTEXT https://PRIVATE-IP:6443 OUTPUT_FILE [deploy|e2e]' >&2; exit 2;; esac
[[ -n "$admin_context" && "$api_server" == https://* && -n "$output" ]] || exit 2
ns="circleguard-$env_name"
[[ ! -e "$output" ]] || { echo 'Refusing to overwrite a kubeconfig file' >&2; exit 1; }
kubectl config get-contexts -o name | grep -qxF -- "$admin_context" || { echo 'Admin context missing' >&2; exit 1; }
kubectl --context "$admin_context" create namespace "$ns" --dry-run=client -o yaml | \
  kubectl --context "$admin_context" apply -f - >/dev/null
sed "s/NAMESPACE/$ns/g" "$ROOT/infra/k8s/rbac/$manifest" | \
  kubectl --context "$admin_context" apply -f - >/dev/null
# The API server may shorten the requested token validity. Refresh this file
# before expiration; never store it in Git or a shared location.
token="$(kubectl --context "$admin_context" -n "$ns" create token "$service_account" --duration=24h)"
[[ -n "$token" ]] || exit 1
ca="$(kubectl config view --context "$admin_context" --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
[[ -n "$ca" ]] || { echo 'Admin context lacks embedded CA data' >&2; exit 1; }
umask 077
cat > "$output" <<EOF_KUBECONFIG
apiVersion: v1
kind: Config
clusters:
  - name: $ns
    cluster:
      certificate-authority-data: $ca
      server: $api_server
contexts:
  - name: $ns
    context:
      cluster: $ns
      user: $service_account
      namespace: $ns
current-context: $ns
users:
  - name: $service_account
    user:
      token: $token
EOF_KUBECONFIG
chmod 600 "$output"
unset token
if [[ "$access" == deploy ]]; then
  KUBECONFIG="$output" kubectl --context "$ns" -n "$ns" auth can-i create deployments | grep -qx yes
  KUBECONFIG="$output" kubectl --context "$ns" -n "$ns" auth can-i create pods --subresource=exec | grep -qx no
  KUBECONFIG="$output" kubectl --context "$ns" -n "$ns" auth can-i create secrets | grep -qx no
else
  KUBECONFIG="$output" kubectl --context "$ns" -n "$ns" auth can-i create pods --subresource=exec | grep -qx yes
  KUBECONFIG="$output" kubectl --context "$ns" -n "$ns" auth can-i create deployments | grep -qx no
  KUBECONFIG="$output" kubectl --context "$ns" -n "$ns" auth can-i get secrets | grep -qx no
fi
KUBECONFIG="$output" kubectl --context "$ns" auth can-i create namespaces | grep -qx no
printf 'Created restricted kubeconfig for %s; store as Jenkins file credential %s.\n' "$ns" "$credential"
