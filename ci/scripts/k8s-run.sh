#!/usr/bin/env bash
# Create environment secrets and deploy the immutable release into its cluster.
# Jenkins supplies a kubeconfig and a private env file as file credentials.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
env_name="${1:-}"
case "$env_name" in dev|stage|prod) ;; *) echo 'environment must be dev, stage or prod' >&2; exit 2;; esac
: "${KUBECONFIG:?Kubernetes kubeconfig file credential required}"
: "${APP_ENV_FILE:?Private application environment file credential required}"
: "${NEXUS_REGISTRY:?Nexus registry address required}"
: "${CG_IMAGE_TAG:?Immutable image tag required}"
[[ -r "$KUBECONFIG" && -r "$APP_ENV_FILE" ]] || { echo 'Kubernetes credential file missing' >&2; exit 1; }
[[ "$NEXUS_REGISTRY" =~ ^[A-Za-z0-9.-]+:[0-9]{2,5}$ ]] || { echo 'NEXUS_REGISTRY must be host:port' >&2; exit 2; }
[[ "$CG_IMAGE_TAG" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]{0,127}$ ]] || exit 2
export KUBE_CONTEXT="circleguard-${env_name}"
export PATH="$ROOT/ci/scripts:$PATH"
# hu13-kubectl.sh is called from an isolated wrapper named kubectl.
cd "$ROOT"
dest="infra/environments/.env.${env_name}"
[[ ! -e "$dest" ]] || { echo "Refusing to overwrite existing $dest" >&2; exit 1; }
umask 077
cp "$APP_ENV_FILE" "$dest"
cleanup() { rm -f -- "$dest"; }
trap cleanup EXIT
bash infra/k8s/secrets.sh "$env_name"
bash infra/k8s/deploy.sh "$env_name" "$NEXUS_REGISTRY" "$CG_IMAGE_TAG"
echo "K3s deployment completed: $env_name / $CG_IMAGE_TAG"
