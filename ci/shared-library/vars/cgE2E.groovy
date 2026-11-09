// HU-07: blocking E2E suite against previously deployed and approved DEV.
// Requires Credentials Binding and HTML Publisher plugins.
def call() {
    withCredentials([
        sshUserPrivateKey(credentialsId: 'circleguard-dev-ssh',
            keyFileVariable: 'E2E_SSH_KEY', usernameVariable: 'E2E_SSH_USER'),
        usernamePassword(credentialsId: 'circleguard-e2e-survey',
            usernameVariable: 'E2E_USERNAME', passwordVariable: 'E2E_PASSWORD'),
        usernamePassword(credentialsId: 'circleguard-e2e-gate',
            usernameVariable: 'E2E_GATE_USERNAME', passwordVariable: 'E2E_GATE_PASSWORD'),
        string(credentialsId: 'circleguard-dev-host', variable: 'E2E_DEV_HOST')
    ]) {
        withEnv(['E2E_DEDICATED_ACCOUNT_ACK=true']) {
            int rc = sh(script: 'bash tests/e2e-playwright/scripts/run-dev.sh', returnStatus: true)
            junit testResults: 'tests/e2e-playwright/test-results/junit.xml', allowEmptyResults: true
            archiveArtifacts artifacts: 'tests/e2e-playwright/test-results/**',
                allowEmptyArchive: true, fingerprint: false
            if (fileExists('tests/e2e-playwright/playwright-report/index.html')) {
                publishHTML(target: [
                    reportName: 'HU-07 Playwright E2E',
                    reportDir: 'tests/e2e-playwright/playwright-report',
                    reportFiles: 'index.html',
                    allowMissing: false, keepAll: true, alwaysLinkToLastBuild: true
                ])
            } else {
                echo 'HU-07: HTML not generated (preflight or test execution failed)'
            }
            if (rc != 0) {
                error("HU-07 E2E failed with exit code ${rc}; no promotion is allowed")
            }
            if (!fileExists('tests/e2e-playwright/playwright-report/index.html')) {
                error('HU-07 completed without required HTML report')
            }
        }
    }
}
