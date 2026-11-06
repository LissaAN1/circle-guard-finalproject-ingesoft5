#!/usr/bin/env bash
# Calcula la siguiente version SemVer desde Conventional Commits (HU-03).
#   Uso: infra/release/version.sh [REF]     (REF por defecto: HEAD)
# Imprime X.Y.Z (sin prefijo "v"). Reglas (docs/agil/01_Estrategia_Branching):
#   tipo con "!" o "BREAKING CHANGE" -> MAJOR | feat -> MINOR | fix -> PATCH
#   docs/test/chore -> sin incremento (se imprime la version vigente)
# Sin tags previos: la primera release es 1.0.0 (entrega de la Parte 1).
set -euo pipefail
ref="${1:-HEAD}"

last_tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' "$ref" 2>/dev/null || true)"
if [[ -z "$last_tag" ]]; then
  echo "1.0.0"
  exit 0
fi

IFS=. read -r major minor patch <<<"${last_tag#v}"
bump="none"
while IFS= read -r -d '' commit; do
  subject="${commit%%$'\n'*}"
  if [[ "$subject" =~ ^[a-z]+(\([a-z0-9-]+\))?!: ]] || grep -q '^BREAKING CHANGE' <<<"$commit"; then
    bump="major"; break
  elif [[ "$subject" =~ ^feat(\(|:|!) ]]; then
    [[ "$bump" != "major" ]] && bump="minor"
  elif [[ "$subject" =~ ^fix(\(|:|!) ]]; then
    [[ "$bump" == "none" ]] && bump="patch"
  fi
done < <(git log --no-merges -z --format='%B' "${last_tag}..${ref}")

case "$bump" in
  major) echo "$((major+1)).0.0" ;;
  minor) echo "${major}.$((minor+1)).0" ;;
  patch) echo "${major}.${minor}.$((patch+1))" ;;
  none)  echo "${major}.${minor}.${patch}" ;;
esac