// Runs the existing Playwright scenarios against Kubernetes, not the old Compose VM.
// E2E is blocking and publishes the same reports as the legacy runner.
def call(Map cfg = [:]) {
    String target = cfg.environment?.toString()?.trim()
    if (!(target in ['dev', 'stage'])) {
        error('cgK8sE2E: environment must be dev or stage')
    }
    String survey = target == 'dev' ? 'circleguard-e2e-survey' : 'circleguard-stage-e2e-survey'
    String gate = target == 'dev' ? 'circleguard-e2e-gate' : 'circleguard-stage-e2e-gate'
    withCredentials([
        file(credentialsId: "kubeconfig-${target}", variable: 'KUBECONFIG'),
        usernamePassword(credentialsId: survey,
            usernameVariable: 'E2E_USERNAME', passwordVariable: 'E2E_PASSWORD'),
        usernamePassword(credentialsId: gate,
            usernameVariable: 'E2E_GATE_USERNAME', passwordVariable: 'E2E_GATE_PASSWORD')
    ]) {
        withEnv(['E2E_DEDICATED_ACCOUNT_ACK=true']) {
            int rc = sh(script: "bash tests/e2e-playwright/scripts/run-k8s.sh ${target}",
                returnStatus: true)
            junit testResults: 'tests/e2e-playwright/test-results/junit.xml', allowEmptyResults: true
            archiveArtifacts artifacts: 'tests/e2e-playwright/test-results/**',
                allowEmptyArchive: true, fingerprint: false
            if (fileExists('tests/e2e-playwright/playwright-report/index.html')) {
                publishHTML(target: [
                    reportName: 'HU-13 Kubernetes Playwright E2E',
                    reportDir: 'tests/e2e-playwright/playwright-report',
                    reportFiles: 'index.html',
                    allowMissing: false, keepAll: true, alwaysLinkToLastBuild: true
                ])
            }
            if (rc != 0) {
                error("Kubernetes E2E failed in ${target} (exit ${rc}); promotion blocked")
            }
            if (!fileExists('tests/e2e-playwright/playwright-report/index.html')) {
                error("Missing Kubernetes E2E report for ${target}")
            }
        }
    }
}
