#!/usr/bin/env bash
# HU-23: issue the Linkerd trust anchor and identity issuer (short-lived, P-256). Keys stay in infra/mesh/.private (git ignores it).
set -euo pipefail
export MSYS2_ARG_CONV_EXCL='/CN='
OUT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.private"
command -v openssl >/dev/null || { echo 'OpenSSL is required' >&2; exit 1; }
if [[ -s "$OUT/ca.crt" && -s "$OUT/issuer.crt" && -s "$OUT/issuer.key" ]]; then echo 'Reusing existing certificates'; exit 0; fi
umask 077; mkdir -p "$OUT"; cd "$OUT"
openssl ecparam -name prime256v1 -genkey -noout -out ca.key
openssl req -x509 -new -key ca.key -sha256 -days 30 -subj '/CN=root.linkerd.cluster.local' -out ca.crt \
  -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign'
openssl ecparam -name prime256v1 -genkey -noout -out issuer.key
openssl req -new -key issuer.key -subj '/CN=identity.linkerd.cluster.local' -out issuer.csr
printf 'basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\n' > issuer.ext
openssl x509 -req -in issuer.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 30 -sha256 -extfile issuer.ext -out issuer.crt
openssl verify -CAfile ca.crt issuer.crt
rm -f issuer.csr issuer.ext ca.srl
echo "Certificates issued in $OUT (valid 30 days)"
