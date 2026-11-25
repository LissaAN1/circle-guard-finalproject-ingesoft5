#!/usr/bin/env bash
# Scan infrastructure configuration or locally built images. A CRITICAL finding
# or a scanner failure returns nonzero and stops publication/promotion.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mode="${1:-}"
case "$mode" in iac|images|secrets) ;; *) echo 'Usage: trivy-run.sh iac|images|secrets' >&2; exit 2;; esac
cd "$ROOT"
image="${CG_TRIVY_IMAGE:-aquasec/trivy:0.76.2}"
mkdir -p ci/reports/trivy
# Vulnerability and Java DBs (~1 GB) live in a named Docker volume mounted at the
# container's world-writable /tmp, so they survive cleanWs and are downloaded
# once instead of on every build (and never fill the workspace).
cache_volume="${CG_TRIVY_CACHE_VOLUME:-circleguard-trivy-cache}"
opts=(--rm --volumes-from "${CG_AGENT_CONTAINER:-circleguard-build-agent}" \
  -w "$PWD" --user "$(id -u):$(id -g)" \
  -v "$cache_volume:/tmp" -e HOME=/tmp -e TRIVY_CACHE_DIR=/tmp/trivy-cache)
scan() {
  docker run "${opts[@]}" "$image" "$@"
}
if [[ "$mode" == iac ]]; then
  scan config --misconfig-scanners terraform \
    --severity CRITICAL --exit-code 1 \
    --format json --output ci/reports/trivy/iac.json infra/terraform
  echo 'Trivy IaC scan completed without CRITICAL findings'
elif [[ "$mode" == images ]]; then
  : "${CG_IMAGE_TAG:?CG_IMAGE_TAG required for image scanning}"
  : "${CG_UNITS:?CG_UNITS required for image scanning}"
  [[ "$CG_IMAGE_TAG" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]{0,127}$ ]] || exit 2
  # The registry is not accessed here: Trivy scans exactly the images built
  # in the local Docker daemon before Jenkins is allowed to publish them.
  # Accepted CVEs live in ci/trivy/images.trivyignore, a path Trivy never loads on its
  # own (it auto-loads ./.trivyignore), so IaC and secret scans cannot inherit them.
  docker_gid="$(stat -c %g /var/run/docker.sock)"
  opts+=(--group-add "$docker_gid" -v /var/run/docker.sock:/var/run/docker.sock)
  for unit in $CG_UNITS; do
    [[ "$unit" =~ ^(auth|identity|promotion|notification|form|file|gateway|dashboard|web)$ ]] || { echo 'Invalid unit' >&2; exit 2; }
    name="$(bash ci/scripts/unit-info.sh "$unit" image)"
    scan image --image-src docker --scanners vuln --severity CRITICAL --exit-code 1 \
      --ignorefile "$PWD/ci/trivy/images.trivyignore" \
      --format json --output "ci/reports/trivy/${unit}.json" \
      "circleguard/${name}:${CG_IMAGE_TAG}"
    echo "Trivy image scan passed: $unit"
  done
else
  # Keep finding details in a temporary file. A secret value must not appear
  # in Jenkins logs, archived artifacts, or the repository.
  umask 077
  report="$(mktemp "$PWD/ci/.secret-scan.XXXXXX")"
  trap 'rm -f -- "$report"' EXIT
  status=0
  scan fs --scanners secret --exit-code 1 --quiet \
    --format json --output "$report" . || status=$?
  if (( status != 0 )); then
    # Print only file paths and rule IDs, never matched secret contents.
    python - "$report" <<'PY_REDACTED'
import json
import sys
try:
    with open(sys.argv[1], encoding='utf-8') as stream:
        data = json.load(stream)
    for result in data.get('Results', []):
        for finding in result.get('Secrets') or []:
            print(f"{result.get('Target', '?')}: {finding.get('RuleID', 'secret detected')}")
except (OSError, ValueError):
    print('Secret scanner failed; review the scanner configuration privately.')
PY_REDACTED
    echo 'Trivy secret scan blocked the pipeline' >&2
    exit "$status"
  fi
  echo 'Trivy secret scan passed: no findings'
fi
