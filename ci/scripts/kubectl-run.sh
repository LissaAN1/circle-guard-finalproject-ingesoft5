#!/usr/bin/env bash
# Install a pinned kubectl on the agent workspace with checksum verification.
# No cluster is contacted during installation, and the downloaded binary is
# kept out of source control.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
version="${CG_KUBECTL_VERSION:-v1.31.4}"
[[ "$version" =~ ^v1\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid kubectl version' >&2; exit 2; }
arch="$(uname -m)"
case "$arch" in x86_64) arch=amd64;; aarch64) arch=arm64;; *) echo "Unsupported architecture: $arch" >&2; exit 2;; esac
cache="$ROOT/ci/.tools"
mkdir -p "$cache"
binary="$cache/kubectl-${version}-linux-${arch}"
if [[ ! -x "$binary" ]]; then
  url="https://dl.k8s.io/release/${version}/bin/linux/${arch}/kubectl"
  tmp="$(mktemp "$cache/kubectl.tmp.XXXXXX")"
  trap 'rm -f "$tmp" "$tmp.sha256"' EXIT
  curl -fsSL --retry 3 "$url" -o "$tmp"
  curl -fsSL --retry 3 "${url}.sha256" -o "$tmp.sha256"
  (cd "$cache" && printf '%s  %s\n' "$(cat "$tmp.sha256")" "$(basename "$tmp")" | sha256sum -c -) >/dev/null
  chmod 755 "$tmp"
  mv "$tmp" "$binary"
fi
exec "$binary" "$@"
