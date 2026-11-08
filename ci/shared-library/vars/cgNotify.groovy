// HU-09: post-build notification on FAILURE or UNSTABLE.
// Called from post{always{}} after checking currentBuild.currentResult.
// Channels:
//   1. GitHub commit status with the build URL (requires github-token credential)
//   2. HTTP webhook (Slack-compatible); enable by setting NOTIFY_WEBHOOK_URL in Jenkins global env
def call(String result) {
    String state = (result == 'FAILURE') ? 'failure' : 'error'
    String mark  = (result == 'FAILURE') ? 'FAILED'  : 'UNSTABLE'
    String link  = env.BUILD_URL ?: ''
    echo "Build ${mark}: ${env.JOB_NAME} #${env.BUILD_NUMBER} — ${link}"

    if (env.GIT_COMMIT?.trim()) {
        try {
            withCredentials([string(credentialsId: 'github-token', variable: 'CG_GH_TOKEN')]) {
                sh(label: 'notify-github-status', script: """
                    curl -fsS -X POST \\
                      -H "Authorization: token \${CG_GH_TOKEN}" \\
                      -H 'Content-Type: application/json' \\
                      -d '{"state":"${state}","target_url":"${link}","description":"Build ${mark}","context":"ci/jenkins"}' \\
                      "https://api.github.com/repos/LissaAN1/circle-guard-finalproject-ingesoft5/statuses/\${GIT_COMMIT}" >/dev/null 2>&1 || true
                """)
            }
        } catch (Exception e) {
            echo "GitHub status skipped: ${e.getMessage()}"
        }
    }

    String webhook = env.NOTIFY_WEBHOOK_URL?.trim()
    if (webhook) {
        try {
            sh(label: 'notify-webhook', script: """
                curl -fsS -X POST -H 'Content-Type: application/json' \\
                  -d '{"text":"Build ${mark}: ${env.JOB_NAME} #${env.BUILD_NUMBER} — ${link}"}' \\
                  "\${NOTIFY_WEBHOOK_URL}" >/dev/null 2>&1 || true
            """)
        } catch (Exception e) {
            echo "Webhook notify skipped: ${e.getMessage()}"
        }
    }
}
