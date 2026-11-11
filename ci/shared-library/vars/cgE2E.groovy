// HU-07: blocking E2E suite against previously deployed and approved DEV or STAGE.
// Requires Credentials Binding and HTML Publisher plugins.
def call(Map cfg = [:]) {
    String envName = cfg.environment?.toString()?.trim()

    if (!(envName in ['dev', 'stage'])) {
        error("cgE2E: environment must be 'dev' or 'stage'")
    }

    String sshCredential = envName == 'dev'
        ? 'circleguard-dev-ssh'
        : 'circleguard-stage-ssh'

    String surveyCredential = envName == 'dev'
        ? 'circleguard-e2e-survey'
        : 'circleguard-stage-e2e-survey'

    String gateCredential = envName == 'dev'
        ? 'circleguard-e2e-gate'
        : 'circleguard-stage-e2e-gate'

    String hostCredential = envName == 'dev'
        ? 'circleguard-dev-host'
        : 'circleguard-stage-host'

    withCredentials([
        sshUserPrivateKey(credentialsId: sshCredential,
            keyFileVariable: 'E2E_SSH_KEY', usernameVariable: 'E2E_SSH_USER'),
        usernamePassword(credentialsId: surveyCredential,
            usernameVariable: 'E2E_USERNAME', passwordVariable: 'E2E_PASSWORD'),
        usernamePassword(credentialsId: gateCredential,
            usernameVariable: 'E2E_GATE_USERNAME', passwordVariable: 'E2E_GATE_PASSWORD'),
        string(credentialsId: hostCredential, variable: 'E2E_TARGET_HOST')
    ]) {
        withEnv(['E2E_DEDICATED_ACCOUNT_ACK=true']) {
            String runner = envName == 'dev'
                ? 'bash tests/e2e-playwright/scripts/run-dev.sh'
                : 'bash tests/e2e-playwright/scripts/run-env.sh stage'

            int rc = withEnv(
                envName == 'dev'
                    ? ["E2E_DEV_HOST=${env.E2E_TARGET_HOST}"]
                    : []
            ) {
                sh(script: runner, returnStatus: true)
            }

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
