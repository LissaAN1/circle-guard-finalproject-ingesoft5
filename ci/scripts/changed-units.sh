#!/usr/bin/env bash
# HU-04: print the pipeline units (one per line) that a change affects.
#   Usage: ci/scripts/changed-units.sh [BASE_REF]
# Rules:
#   * services/circleguard-<x>-service/** -> unit <x>
#   * mobile/**                            -> unit web
#   * repository root build files (Gradle build/settings/wrapper, lombok.config, Jenkinsfile,
#     ci/**, infra/environments/**, .dockerignore) affect every unit -> ALL units
#   * docs, infra, .github and other files -> no unit (nothing to build)
#   * no BASE_REF, unknown ref, or FORCE_ALL=true -> ALL units
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
base="${1:-}"

mapfile -t all < <("$HERE/unit-info.sh" list)

print_all() { printf '%s\n' "${all[@]}"; }

if [[ "${FORCE_ALL:-false}" == "true" || -z "$base" ]]; then print_all; exit 0; fi
if ! git -C "$ROOT" rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
  echo "WARN: base '$base' not found; running every unit" >&2
  print_all; exit 0
fi

declare -A hit=()
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  case "$file" in
    services/circleguard-*-service/*)
      rest="${file#services/circleguard-}"; hit["${rest%%-service/*}"]=1 ;;
    mobile/*) hit[web]=1 ;;
    build.gradle.kts|settings.gradle.kts|gradle.properties|lombok.config|gradlew|gradlew.bat|gradle/*|Jenkinsfile|.dockerignore|ci/*|infra/environments/*)
      print_all; exit 0 ;;
  esac
done < <(git -C "$ROOT" diff --name-only "$base...HEAD")

for u in "${all[@]}"; do [[ -n "${hit[$u]:-}" ]] && echo "$u"; done
exit 0
