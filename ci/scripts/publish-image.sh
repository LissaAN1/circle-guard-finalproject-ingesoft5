#!/usr/bin/env bash
# HU-04: push one unit's image to the Nexus Docker registry.
#   Usage: NEXUS_REGISTRY=host:8082 NEXUS_USER=... NEXUS_PASSWORD=... ci/scripts/publish-image.sh <unit> <tag>
# Credentials come from the environment (Jenkins withCredentials); the password is read from stdin, never argv.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
unit="${1:?unit required}"; tag="${2:?tag required}"
[[ "$tag" != "latest" ]] || { echo "ERROR: the 'latest' tag is forbidden" >&2; exit 1; }
: "${NEXUS_REGISTRY:?NEXUS_REGISTRY (host:port) is required}"
: "${NEXUS_USER:?NEXUS_USER is required}"
: "${NEXUS_PASSWORD:?NEXUS_PASSWORD is required}"

image="$("$HERE/unit-info.sh" "$unit" image)"
local_ref="circleguard/${image}:${tag}"
remote_ref="${NEXUS_REGISTRY}/circleguard/${image}:${tag}"

printf '%s' "$NEXUS_PASSWORD" | docker login "$NEXUS_REGISTRY" -u "$NEXUS_USER" --password-stdin >/dev/null
docker tag "$local_ref" "$remote_ref"
docker push "$remote_ref"
docker logout "$NEXUS_REGISTRY" >/dev/null 2>&1 || true
echo "published $remote_ref"
