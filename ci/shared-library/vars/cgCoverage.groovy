// HU-05: publishes the JaCoCo line coverage of the tested services in Jenkins (coverage trend on the
// build page) and keeps the HTML report as an artifact. Does not decide pass/fail: the SonarQube
// quality gate (cgAnalysis) is the blocking check.
def call() {
    if (!fileExists('services')) { return }
    jacoco(
        execPattern: 'services/*/build/jacoco/*.exec',
        classPattern: 'services/*/build/classes',
        sourcePattern: 'services/*/src/main/java',
        inclusionPattern: '**/*.class',
        skipCopyOfSrcFiles: true
    )
    archiveArtifacts artifacts: 'services/*/build/reports/jacoco/test/html/**', allowEmptyArchive: true
}
