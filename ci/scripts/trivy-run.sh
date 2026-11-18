#!/usr/bin/env bash
# Scan infrastructure configuration or locally built images. A CRITICAL finding
# or a scanner failure returns nonzero and stops publication/promotion.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mode="${1:-}"
case "$mode" in iac|images) ;; *) echo 'Usage: hu13-trivy.sh iac|images' >&2; exit 2;; esac
cd "$ROOT"
image="${CG_TRIVY_IMAGE:-aquasec/trivy:0.76.2}"
mkdir -p ci/reports/trivy ci/.trivy-cache
opts=(--rm --volumes-from "${CG_AGENT_CONTAINER:-circleguard-build-agent}" \
  -w "$PWD" --user "$(id -u):$(id -g)" \
  -e HOME=/tmp -e TRIVY_CACHE_DIR="$PWD/ci/.trivy-cache")
scan() {
  docker run "${opts[@]}" "$image" "$@"
}
if [[ "$mode" == iac ]]; then
  scan config --misconfig-scanners terraform \
    --severity CRITICAL --exit-code 1 \
    --format json --output ci/reports/trivy/iac.json infra/terraform
  echo 'Trivy IaC scan completed without CRITICAL findings'
else
  : "${CG_IMAGE_TAG:?CG_IMAGE_TAG required for image scanning}"
  : "${CG_UNITS:?CG_UNITS required for image scanning}"
  [[ "$CG_IMAGE_TAG" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]{0,127}$ ]] || exit 2
  # The registry is not accessed here: Trivy scans exactly the images built
  # in the local Docker daemon before Jenkins is allowed to publish them.
  docker_gid="$(stat -c %g /var/run/docker.sock)"
  opts+=(--group-add "$docker_gid" -v /var/run/docker.sock:/var/run/docker.sock)
  for unit in $CG_UNITS; do
    [[ "$unit" =~ ^(auth|identity|promotion|notification|form|file|gateway|dashboard|web)$ ]] || { echo 'Invalid unit' >&2; exit 2; }
    name="$(bash ci/scripts/unit-info.sh "$unit" image)"
    scan image --image-src docker --scanners vuln --severity CRITICAL --exit-code 1 \
      --format json --output "ci/reports/trivy/${unit}.json" \
      "circleguard/${name}:${CG_IMAGE_TAG}"
    echo "Trivy image scan passed: $unit"
  done
fi
