// HU-08: deploys an image version to an environment via SSH.
// cfg.environment: 'dev' | 'stage' | 'prod'
// cfg.appVersion:  image tag set by cgPackage (env.CG_IMAGE_TAG)
// cfg.host:        optional override; defaults to EC2_<ENV>_HOST global env var
def call(Map cfg = [:]) {
    String envName    = cfg.environment
    String appVersion = cfg.appVersion
    if (!envName)          error('cgDeploy: environment is required')
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
    withCredentials([sshUserPrivateKey(credentialsId: 'ec2-ssh-key',
                                       keyFileVariable: 'SSH_KEY',
                                       usernameVariable: 'SSH_USER')]) {
        sh(label: 'upload-compose-files', script: """
            scp -o StrictHostKeyChecking=accept-new -o BatchMode=yes \\
              -i "\${SSH_KEY}" \\
              infra/environments/compose.base.yaml \\
              infra/environments/compose.${envName}.yaml \\
              "\${SSH_USER}@${host}:/opt/circleguard/environments/"
        """)
        sh(label: 'upload-deploy-script', script: """
            scp -o StrictHostKeyChecking=accept-new -o BatchMode=yes \\
              -i "\${SSH_KEY}" \\
              ci/deploy/deploy-remote.sh \\
              "\${SSH_USER}@${host}:/tmp/cg-deploy-remote.sh"
        """)
        sh(label: "deploy-${envName}", script: """
            ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes \\
              -i "\${SSH_KEY}" \\
              "\${SSH_USER}@${host}" \\
              "bash /tmp/cg-deploy-remote.sh '${envName}' '${appVersion}'; rm -f /tmp/cg-deploy-remote.sh"
        """)
    }
}
