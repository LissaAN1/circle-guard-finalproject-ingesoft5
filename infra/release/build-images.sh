#!/usr/bin/env bash
# Construye (y opcionalmente publica) las 9 imagenes de CircleGuard (HU-03).
#   Uso: infra/release/build-images.sh X.Y.Z [--push] [servicio ...]
# Variables:
#   REGISTRY    host:puerto del repositorio Docker de Nexus (obligatoria con --push)
#   NEXUS_USER / NEXUS_PASSWORD  credenciales (las inyecta Jenkins; nunca en el repo)
# Etiquetas publicadas: <REGISTRY>/circleguard/<imagen>:X.Y.Z  (nunca "latest")
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

version="${1:?Uso: build-images.sh X.Y.Z [--push] [servicio ...]}"; shift
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version invalida: $version" >&2; exit 1; }
push=false; [[ "${1:-}" == "--push" ]] && { push=true; shift; }

all=(auth identity promotion notification form file gateway dashboard web)
targets=("${@:-${all[@]}}")
vcs_ref="$(git rev-parse --short HEAD)"
registry="${REGISTRY:-}"
if $push; then
  : "${REGISTRY:?Defina REGISTRY (host:puerto de Nexus)}"
  : "${NEXUS_USER:?Defina NEXUS_USER}"; : "${NEXUS_PASSWORD:?Defina NEXUS_PASSWORD}"
  printf '%s' "$NEXUS_PASSWORD" | docker login "$registry" -u "$NEXUS_USER" --password-stdin
fi

for t in "${targets[@]}"; do
  if [[ "$t" == "web" ]]; then
    image="circleguard-web"; file="mobile/Dockerfile"; context="mobile"
  else
    image="circleguard-$t-service"; file="services/$image/Dockerfile"; context="."
  fi
  ref="circleguard/${image}:${version}"; [[ -n "$registry" ]] && ref="${registry}/${ref}"
  echo ">> build $ref"
  docker build -f "$file" --build-arg VERSION="$version" --build-arg VCS_REF="$vcs_ref" -t "$ref" "$context"
  $push && docker push "$ref"
done