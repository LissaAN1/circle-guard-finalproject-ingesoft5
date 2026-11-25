// HU-21: Locust load test against the Kubernetes environment; missing a declared target
// in tests/performance/targets.json fails the stage and blocks promotion to prod.
def call(Map cfg = [:]) {
    String target = cfg.environment?.toString()?.trim()
    if (!(target in ['dev', 'stage'])) {
        error('cgPerformance: environment must be dev or stage')
    }
    String survey = target == 'dev' ? 'circleguard-e2e-survey' : 'circleguard-stage-e2e-survey'
    withCredentials([
        file(credentialsId: "kubeconfig-e2e-${target}", variable: 'KUBECONFIG'),
        usernamePassword(credentialsId: survey,
            usernameVariable: 'E2E_USERNAME', passwordVariable: 'E2E_PASSWORD')
    ]) {
        int rc = sh(script: "bash tests/performance/run-k8s.sh ${target}", returnStatus: true)
        archiveArtifacts artifacts: 'ci/reports/performance/**', allowEmptyArchive: true, fingerprint: false
        if (fileExists('ci/reports/performance/locust.html')) {
            publishHTML(target: [
                reportName: 'HU-21 Locust',
                reportDir: 'ci/reports/performance',
                reportFiles: 'locust.html',
                allowMissing: false, keepAll: true, alwaysLinkToLastBuild: true
            ])
        }
        if (rc != 0) {
            error("Locust missed the declared targets in ${target} (exit ${rc}); promotion blocked")
        }
    }
}
