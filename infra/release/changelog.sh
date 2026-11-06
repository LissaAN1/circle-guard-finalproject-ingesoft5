#!/usr/bin/env bash
# Genera las release notes de una version desde Conventional Commits (HU-03).
#   Uso: infra/release/changelog.sh X.Y.Z [REF]  -> imprime la seccion en Markdown
# Para actualizar el archivo: ver infra/release/release.sh (antepone la seccion a CHANGELOG.md).
set -euo pipefail
version="${1:?Uso: changelog.sh X.Y.Z [REF]}"
ref="${2:-HEAD}"

last_tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' "$ref" 2>/dev/null || true)"
range="$ref"; [[ -n "$last_tag" ]] && range="${last_tag}..${ref}"

section() { # $1 = titulo, $2 = regex del tipo
  local lines
  lines="$(git log --no-merges --format='%s|%h' "$range" | grep -E "^($2)(\(|:|!)" | \
    awk -F'|' '{printf "- %s (%s)\n", $1, $2}' || true)"
  [[ -n "$lines" ]] && printf '### %s\n\n%s\n\n' "$1" "$lines"
  return 0
}

printf '## [%s] - %s\n\n' "$version" "$(date +%Y-%m-%d)"
section "Features" "feat"
section "Fixes" "fix"
section "Tests" "test"
section "Documentation" "docs"
section "Chores" "chore"