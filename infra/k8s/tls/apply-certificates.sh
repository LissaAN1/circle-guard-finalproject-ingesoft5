#!/usr/bin/env bash
# Install the already issued certificate in the selected Kubernetes namespace.
# Secret values pass through stdin and are never printed or stored in Git.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$HERE/../lib.sh"
env="${1:-}"
case "$env" in dev|stage|prod) ;; *) echo 'Usage: apply-certificates.sh dev|stage|prod' >&2; exit 2 ;; esac
cert="$HERE/.private/$env/tls.crt"
key="$HERE/.private/$env/tls.key"
ca="$HERE/.private/ca.crt"
[[ -s "$cert" && -s "$key" && -s "$ca" ]] || { echo 'Issue certificates first' >&2; exit 1; }
openssl verify -CAfile "$ca" -verify_hostname "$env.circleguard.test" "$cert" >/dev/null
select_cluster "$env"
ns="circleguard-$env"
# The namespace must already exist; never create it in the wrong cluster.
kc get namespace "$ns" >/dev/null
kc -n "$ns" create secret tls circleguard-ingress-tls \
  --cert="$cert" --key="$key" --dry-run=client -o yaml | \
  kc -n "$ns" apply -f - >/dev/null
kc -n "$ns" get secret circleguard-ingress-tls \
  -o jsonpath='{.type}' | grep -qx 'kubernetes.io/tls'
printf 'TLS Secret ready in %s\n' "$ns"
