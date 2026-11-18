#!/usr/bin/env bash
# Run an environment plan or apply with an isolated, pinned Terraform CLI.
# The workspace is shared with the build agent; private backend and variable
# files are supplied by Jenkins credentials, never from the repository.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
env_name="${1:-}"; action="${2:-}"
case "$env_name" in dev|stage|prod) ;; *) echo 'environment must be dev, stage or prod' >&2; exit 2;; esac
case "$action" in plan|apply) ;; *) echo 'action must be plan or apply' >&2; exit 2;; esac
: "${TF_BACKEND_FILE:?Jenkins backend.hcl file credential is required}"
: "${TF_VARS_FILE:?Jenkins terraform.tfvars file credential is required}"
: "${AWS_ACCESS_KEY_ID:?AWS credentials are required}"
: "${AWS_SECRET_ACCESS_KEY:?AWS credentials are required}"
: "${AWS_DEFAULT_REGION:?AWS_DEFAULT_REGION is required}"
[[ -r "$TF_BACKEND_FILE" && -r "$TF_VARS_FILE" ]] || { echo 'Terraform credential file missing' >&2; exit 1; }
cd "$ROOT"
dir="infra/terraform/environments/$env_name"
plan="$dir/terraform.tfplan"
# Never silently run Terraform against a local state or an unconfigured backend.
[[ -f "$dir/versions.tf" ]] && grep -q 'backend "s3"' "$dir/versions.tf" || { echo 'Remote S3 backend not configured' >&2; exit 1; }
TF_IMAGE="${CG_TERRAFORM_IMAGE:-hashicorp/terraform:1.14.0}"
terraform_run() {
  docker run --rm --volumes-from "${CG_AGENT_CONTAINER:-circleguard-build-agent}" \
    --user "$(id -u):$(id -g)" -w "$PWD" \
    -e HOME=/tmp -e TF_IN_AUTOMATION=1 -e TF_INPUT=0 \
    -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN \
    -e AWS_DEFAULT_REGION -e AWS_REGION \
    "$TF_IMAGE" "$@"
}
terraform_run -chdir="$dir" init -input=false -reconfigure -backend-config="$TF_BACKEND_FILE"
case "$action" in
  plan)
    rm -f "$plan"
    terraform_run -chdir="$dir" plan -input=false -lock-timeout=5m \
      -var-file="$TF_VARS_FILE" -out=terraform.tfplan
    [[ -s "$plan" ]] || { echo "Terraform did not produce $plan" >&2; exit 1; }
    echo "Plan ready: $env_name"
    ;;
  apply)
    [[ -s "$plan" ]] || { echo "Missing approved plan for $env_name" >&2; exit 1; }
    terraform_run -chdir="$dir" apply -input=false -lock-timeout=5m terraform.tfplan
    rm -f "$plan"
    echo "Applied approved plan: $env_name"
    ;;
esac
