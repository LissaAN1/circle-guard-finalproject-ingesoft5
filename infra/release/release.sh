#!/usr/bin/env bash
# Flujo de release (HU-03), ejecutado sobre main tras fusionar dev (merge commit):
#   1) calcula la version  2) antepone las release notes a CHANGELOG.md
#   3) crea el tag anotado vX.Y.Z  4) (opcional) construye y publica imagenes
#   Uso: infra/release/release.sh [--push-images] [--push-tag]
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
[[ "$(git branch --show-current)" == "main" ]] || { echo "Ejecutar desde main" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Arbol de trabajo sucio" >&2; exit 1; }
: "${JIRA_KEY:?Defina JIRA_KEY con la clave Jira del elemento que disparo el release (ej. export JIRA_KEY=PI-17)}"

version="$(infra/release/version.sh)"
if git rev-parse -q --verify "refs/tags/v${version}" >/dev/null; then
  echo "v${version} ya existe: no hay cambios que liberar (solo docs/test/chore)."; exit 0
fi

notes="$(infra/release/changelog.sh "$version")"
{ printf '# Changelog\n\n'; printf '%s\n' "$notes"; tail -n +3 CHANGELOG.md 2>/dev/null || true; } > CHANGELOG.md.new
mv CHANGELOG.md.new CHANGELOG.md
git add CHANGELOG.md
git commit -m "docs(release): add changelog for v${version}" -m "Refs: ${JIRA_KEY}"
git tag -a "v${version}" -m "release v${version}"

[[ " $* " == *" --push-tag "* ]]    && git push origin main "v${version}"
[[ " $* " == *" --push-images "* ]] && infra/release/build-images.sh "$version" --push
echo "Release v${version} lista."