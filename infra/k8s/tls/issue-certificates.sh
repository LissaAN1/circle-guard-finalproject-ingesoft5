#!/usr/bin/env bash
# Issue a short-lived certificate for each stable Ingress hostname.
# The private CA is an explicit trust anchor, not a publicly trusted issuer.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/.private"
[[ ! -e "$OUT/ca.key" && ! -e "$OUT/ca.crt" ]] || {
  echo 'Existing CA found: refuse to rotate keys without a coordinated plan' >&2
  exit 1
}
command -v openssl >/dev/null || { echo 'OpenSSL is required' >&2; exit 1; }
umask 077
mkdir -p "$OUT"
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 30 \
  -subj '/CN=CircleGuard Test CA' \
  -addext 'basicConstraints=critical,CA:TRUE' \
  -addext 'keyUsage=critical,keyCertSign,cRLSign' \
  -keyout "$OUT/ca.key" -out "$OUT/ca.crt" >/dev/null 2>&1
for env in dev stage prod; do
  host="$env.circleguard.test"
  dir="$OUT/$env"
  mkdir -p "$dir"
  openssl req -new -newkey rsa:2048 -nodes -sha256 \
    -subj "/CN=$host" -keyout "$dir/tls.key" -out "$dir/tls.csr" >/dev/null 2>&1
  cat > "$dir/extensions.cnf" <<EOF_EXT
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:$host
EOF_EXT
  openssl x509 -req -in "$dir/tls.csr" -CA "$OUT/ca.crt" -CAkey "$OUT/ca.key" \
    -CAcreateserial -out "$dir/tls.crt" -days 30 -sha256 \
    -extfile "$dir/extensions.cnf" >/dev/null 2>&1
  openssl verify -CAfile "$OUT/ca.crt" -verify_hostname "$host" "$dir/tls.crt"
  rm -f "$dir/tls.csr" "$dir/extensions.cnf"
done
printf 'TLS certificates issued and verified. Trust anchor: %s/ca.crt\n' "$OUT"
