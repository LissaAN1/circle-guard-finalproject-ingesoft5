#!/usr/bin/env bash
# HU-01: single entry point to (re)construct the existing CI/CD EC2 tool stack.
# Usage: JENKINS_TEACHER_USER=<login> bash infra/bootstrap-cicd.sh
# IAM, EC2 instances, SSH keys and Docker are supplied by TEC-04.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$HERE/bootstrap-connectivity.sh"
bash "$HERE/bootstrap-jenkins.sh"
bash "$HERE/bootstrap-sonarqube.sh"
bash "$HERE/bootstrap-nexus.sh"

printf '\nHU-01 bootstrap applied. Validate URLs, users, registry and idempotency before closing Jira.\n'
