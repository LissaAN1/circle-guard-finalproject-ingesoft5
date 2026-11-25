// HU-21: OWASP ZAP baseline against the Kubernetes environment. The report is always
// published; a FAIL rule from ci/zap/rules.tsv or a scanner error fails the stage.
def call(Map cfg = [:]) {
    String target = cfg.environment?.toString()?.trim()
    if (!(target in ['dev', 'stage'])) {
        error('cgZap: environment must be dev or stage')
    }
    withCredentials([file(credentialsId: "kubeconfig-e2e-${target}", variable: 'KUBECONFIG')]) {
        int rc = sh(script: "bash ci/scripts/zap-run.sh ${target}", returnStatus: true)
        archiveArtifacts artifacts: 'ci/reports/zap/**', allowEmptyArchive: true, fingerprint: false
        if (fileExists('ci/reports/zap/zap-report.html')) {
            publishHTML(target: [
                reportName: 'HU-21 OWASP ZAP',
                reportDir: 'ci/reports/zap',
                reportFiles: 'zap-report.html',
                allowMissing: false, keepAll: true, alwaysLinkToLastBuild: true
            ])
        }
        if (rc != 0) {
            error("ZAP baseline failed in ${target} (exit ${rc}); promotion blocked")
        }
    }
}
