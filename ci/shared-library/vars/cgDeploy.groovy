// HU-08: deploys an image version to an environment via SSH.
// cfg.environment: 'dev' | 'stage' | 'prod'
// cfg.appVersion:  image tag set by cgPackage (env.CG_IMAGE_TAG)
// cfg.host:        optional override; defaults to EC2_<ENV>_HOST global env var
def call(Map cfg = [:]) {
    String envName    = cfg.environment
    String appVersion = cfg.appVersion
    if (!envName) {
        error('cgDeploy: environment is required')
    }
    if (!(envName in ['dev', 'stage', 'prod'])) {
        error("cgDeploy: unsupported environment '${envName}'")
    }
    if (!appVersion?.trim()) error('cgDeploy: appVersion is required')
    if (!(appVersion ==~ /^[0-9A-Za-z][0-9A-Za-z._+\-]{0,127}$/)) {
        error("cgDeploy: appVersion '${appVersion}' contains invalid characters")
    }
    String host = cfg.host?.trim() ?: env["EC2_${envName.toUpperCase()}_HOST"]?.trim()
    if (!host) {
        error("cgDeploy: no host for ${envName}; set EC2_${envName.toUpperCase()}_HOST or pass host:")
    }
    int reachable = sh(script: "nc -z -w 10 '${host}' 22", returnStatus: true)
    if (reachable != 0) {
        error("cgDeploy: SSH connectivity check failed for ${envName} (${host}:22). Deployment aborted.")
    }
    echo "Deploying to ${envName}: ${appVersion}"

    withCredentials([sshUserPrivateKey(
        credentialsId: 'ec2-ssh-key',
        keyFileVariable: 'SSH_KEY',
        usernameVariable: 'SSH_USER'
    )]) {
        withEnv(["CG_DEPLOY_HOST=${host}",
                 "CG_DEPLOY_ENV=${envName}",
                 "CG_DEPLOY_VERSION=${appVersion}"]) {
            sh(label: "deploy-${envName}", script: '''#!/usr/bin/env bash
set -euo pipefail

ssh_opts=(
  -o StrictHostKeyChecking=accept-new
  -o BatchMode=yes
  -o IdentitiesOnly=yes
  -i "$SSH_KEY"
)
target="${SSH_USER}@${CG_DEPLOY_HOST}"

# Preflight: SSH and non-interactive sudo.
ssh "${ssh_opts[@]}" "$target" 'sudo -n true'

# Unique, private directory on the target.
remote_tmp="$(
  ssh "${ssh_opts[@]}" "$target" \
    'mktemp -d /tmp/cg-deploy.XXXXXXXX'
)"

cleanup() {
  ssh "${ssh_opts[@]}" "$target" \
    "rm -rf -- '$remote_tmp'" || true
}
trap cleanup EXIT

scp "${ssh_opts[@]}" \
  "infra/environments/compose.base.yaml" \
  "infra/environments/compose.${CG_DEPLOY_ENV}.yaml" \
  "ci/deploy/deploy-remote.sh" \
  "$target:$remote_tmp/"

# Preserve the private .env and init-db.sql.
ssh "${ssh_opts[@]}" "$target" \
  "sudo -n install -m 644 \
  '$remote_tmp/compose.base.yaml' \
  /opt/circleguard/environments/compose.base.yaml && \
  sudo -n install -m 644 \
  '$remote_tmp/compose.${CG_DEPLOY_ENV}.yaml' \
  '/opt/circleguard/environments/compose.${CG_DEPLOY_ENV}.yaml' && \
  sudo -n bash '$remote_tmp/deploy-remote.sh' \
  '$CG_DEPLOY_ENV' '$CG_DEPLOY_VERSION'"
''')
        }
    }
}
