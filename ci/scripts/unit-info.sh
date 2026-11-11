#!/usr/bin/env bash
# HU-04: resolve a pipeline unit from ci/units.conf.
#   Usage: ci/scripts/unit-info.sh list
#          ci/scripts/unit-info.sh <unit> kind|tests|quality|dir|gradle|dockerfile|context|image
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONF="${CG_UNITS_CONF:-$ROOT/ci/units.conf}"

units() { awk '!/^[[:space:]]*(#|$)/ {print $1}' "$CONF"; }

if [[ "${1:-}" == "list" ]]; then units; exit 0; fi

unit="${1:?unit required}"; field="${2:?field required}"
row="$(awk -v u="$unit" '!/^[[:space:]]*(#|$)/ && $1==u {print $2" "$3" "($4==""?"none":$4)}' "$CONF")"
[[ -n "$row" ]] || { echo "unknown unit: $unit" >&2; exit 2; }
read -r kind tests quality <<<"$row"

case "$field" in
  kind)  echo "$kind" ;;
  tests) echo "$tests" ;;
  quality) echo "$quality" ;;
  dir)        [[ "$kind" == service ]] && echo "services/circleguard-$unit-service" || echo "mobile" ;;
  gradle)     [[ "$kind" == service ]] && echo ":services:circleguard-$unit-service" || echo "" ;;
  dockerfile) [[ "$kind" == service ]] && echo "services/circleguard-$unit-service/Dockerfile" || echo "mobile/Dockerfile" ;;
  context)    [[ "$kind" == service ]] && echo "." || echo "mobile" ;;
  image)      [[ "$kind" == service ]] && echo "circleguard-$unit-service" || echo "circleguard-web" ;;
  *) echo "unknown field: $field" >&2; exit 2 ;;
esac
