#!/usr/bin/env bash
# HU-04/HU-05/HU-08/HU-09: deploys the CI pipeline layer on the existing Jenkins EC2 (build agent, shared
# library, multibranch job, rollback job, CD deploy stages, SonarQube analysis, optional webhook relay and Nexus publishing).
# Idempotent; builds on HU-01.
#
# Usage:  bash infra/bootstrap-ci.sh
# Optional environment (all secrets travel over SSH stdin, never as arguments or files in Git):
#   GITHUB_TOKEN              token for branch scanning and commit statuses (scopes: repo:status, public_repo)
#   NEXUS_REGISTRY            Nexus Docker registry as <private-ip>:8082 (enables publishing from dev/main)
#   NEXUS_PUBLISHER_PASSWORD  password of the Nexus user cg-publisher (read it on the Nexus EC2)
#   SONAR_HOST_URL            SonarQube as http://<private-ip>:9000 (HU-05: enables the Analysis stage / quality gate);
#                             the analysis token is fetched from the SonarQube EC2 (it must be running)
#   SONAR_TOKEN               optional: use this analysis token instead of fetching it
#   SMEE_URL                  smee.io channel URL used as webhook relay
#   NOTIFY_WEBHOOK_URL        Slack-compatible webhook URL for failure notifications (HU-09, stored as secret)
#   EC2_DEV_HOST              public IP of circleguard-dev (enables auto-deploy to dev and rollback)
#   EC2_STAGE_HOST            public IP of circleguard-stage (enables auto-deploy to stage from main)
#   EC2_PROD_HOST             public IP of circleguard-prod (enables deploy to prod after approval)
#   EC2_SSH_KEY_B64           base64-encoded EC2 SSH private key (required for deploy/rollback jobs)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap-common.sh
source "$HERE/bootstrap-common.sh"

bootstrap_require
bootstrap_target jenkins

[[ -z "${NEXUS_REGISTRY:-}" || "$NEXUS_REGISTRY" =~ ^[A-Za-z0-9._-]+:[0-9]+$ ]] \
  || die 'NEXUS_REGISTRY must look like 172.31.5.84:8082'
[[ -z "${SONAR_HOST_URL:-}" || "$SONAR_HOST_URL" =~ ^http://[A-Za-z0-9._-]+:[0-9]+$ ]] \
  || die 'SONAR_HOST_URL must look like http://172.31.6.46:9000'
[[ -z "${SMEE_URL:-}" || "$SMEE_URL" =~ ^https://smee\.io/[A-Za-z0-9_-]+$ ]] \
  || die 'SMEE_URL must look like https://smee.io/<channel>'

# HU-05: the analysis token is created once on the SonarQube EC2 and read from there (never typed or printed).
if [[ -n "${SONAR_HOST_URL:-}" && -z "${SONAR_TOKEN:-}" ]]; then
  bootstrap_target sonarqube
  SONAR_TOKEN="$(bootstrap_ssh 'sudo python3 /opt/circleguard/sonarqube/configure.py --token')" \
    || die 'Could not read the SonarQube analysis token; run infra/bootstrap-sonarqube.sh first'
  [[ -n "$SONAR_TOKEN" ]] || die 'SonarQube returned an empty analysis token'
  bootstrap_target jenkins
fi

bootstrap_ssh 'sudo docker compose version >/dev/null && command -v python3 >/dev/null' \
  || die 'Jenkins EC2 needs Docker Compose and Python 3 (TEC-04)'
bootstrap_ssh 'sudo test -f /opt/circleguard/jenkins/jenkins.secrets.env' \
  || die 'HU-01 Jenkins is not initialized; run infra/bootstrap-jenkins.sh first'

src="$HERE/bootstrap/jenkins"
dst=/opt/circleguard/jenkins
bootstrap_upload "$src/Dockerfile" "$dst/Dockerfile"
bootstrap_upload "$src/compose.yaml" "$dst/compose.yaml"
bootstrap_upload "$src/casc.yaml" "$dst/casc.yaml"
bootstrap_upload "$src/casc.d/10-ci.yaml" "$dst/casc.d/10-ci.yaml"
bootstrap_upload "$src/agent/Dockerfile" "$dst/agent/Dockerfile"
bootstrap_upload "$src/ci-remote.sh" "$dst/ci-remote.sh"

{
  printf 'JENKINS_PUBLIC_URL=http://%s:8080/\n' "$BOOTSTRAP_TARGET_IP"
  [[ -z "${NEXUS_REGISTRY:-}" ]]           || printf 'NEXUS_REGISTRY=%s\n' "$NEXUS_REGISTRY"
  [[ -z "${SONAR_HOST_URL:-}" ]]           || printf 'SONAR_HOST_URL=%s\n' "$SONAR_HOST_URL"
  [[ -z "${SONAR_TOKEN:-}" ]]              || printf 'SONAR_TOKEN=%s\n' "$SONAR_TOKEN"
  [[ -z "${GITHUB_TOKEN:-}" ]]             || printf 'GITHUB_TOKEN=%s\n' "$GITHUB_TOKEN"
  [[ -z "${NEXUS_PUBLISHER_PASSWORD:-}" ]] || printf 'NEXUS_PUBLISHER_PASSWORD=%s\n' "$NEXUS_PUBLISHER_PASSWORD"
  [[ -z "${SMEE_URL:-}" ]]                 || printf 'SMEE_URL=%s\n' "$SMEE_URL"
} | bootstrap_ssh "sudo bash '$dst/ci-remote.sh'"

printf '\nJenkins: http://%s:8080  (job: circleguard; node: build-agent)\n' "$BOOTSTRAP_TARGET_IP"
printf 'Check the agent is online and run a scan; see docs/operaciones/hu-04-pipeline-ci.md\n'
