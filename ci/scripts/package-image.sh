#!/usr/bin/env bash
# HU-04: build one unit's Docker image with an immutable tag (never "latest").
#   Usage: ci/scripts/package-image.sh <unit> <tag>      e.g. form 1.0.0-ci.12.ab12cd3
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
unit="${1:?unit required}"; tag="${2:?tag required}"
[[ "$tag" != "latest" ]] || { echo "ERROR: the 'latest' tag is forbidden" >&2; exit 1; }
[[ "$tag" =~ ^[0-9A-Za-z][0-9A-Za-z._-]{0,127}$ ]] || { echo "ERROR: invalid tag '$tag'" >&2; exit 1; }

image="$("$HERE/unit-info.sh" "$unit" image)"
dockerfile="$("$HERE/unit-info.sh" "$unit" dockerfile)"
context="$("$HERE/unit-info.sh" "$unit" context)"
vcs_ref="$(git -C "$ROOT" rev-parse --short=7 HEAD)"

cd "$ROOT"
echo ">> docker build circleguard/${image}:${tag}"
docker build -f "$dockerfile" \
  --build-arg VERSION="$tag" --build-arg VCS_REF="$vcs_ref" \
  -t "circleguard/${image}:${tag}" "$context"
