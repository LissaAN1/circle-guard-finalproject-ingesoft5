// HU-06: runs the Testcontainers integration tests (Gradle task "integrationTest") of the changed
// services and publishes the JUnit report. Only services that actually contain @Tag("integration")
// tests are executed. allowEmptyResults: true so that pre-existing test infrastructure bugs do not
// block Analysis/Package; set to false once integration test reliability is confirmed.
//
// Requirements on the agent: Docker reachable (the build-agent already mounts the Docker socket).
// If Testcontainers cannot reach the containers it starts, define TC_HOST_OVERRIDE on the job
// (for example the Docker host gateway address) and it is passed as TESTCONTAINERS_HOST_OVERRIDE.
def call() {
    List<String> withIntegration = []
    (env.CG_SERVICES.split() as List<String>).each { u ->
        // unit-info.sh <unit> gradle  ->  :services:circleguard-form-service
        String gradlePath = sh(script: "ci/scripts/unit-info.sh ${u} gradle", returnStdout: true).trim()
        String dir = gradlePath.substring(1).replace(':', '/')
        int found = sh(script: "grep -rqs --include='*.java' 'Tag(\"integration\")' ${dir}/src/test", returnStatus: true)
        if (found == 0) { withIntegration << u }
    }

    if (!withIntegration) {
        echo "No integration tests in: ${env.CG_SERVICES ?: '(none)'}"
        return
    }

    echo "Integration tests for: ${withIntegration.join(', ')}"
    List<String> extraEnv = env.TC_HOST_OVERRIDE ? ["TESTCONTAINERS_HOST_OVERRIDE=${env.TC_HOST_OVERRIDE}"] : []
    try {
        withEnv(extraEnv) {
            timeout(time: 30, unit: 'MINUTES') {
                cgGradle(withIntegration, 'integrationTest')
            }
        }
    } finally {
        junit testResults: '**/build/test-results/integrationTest/*.xml', allowEmptyResults: true
        archiveArtifacts artifacts: '**/build/reports/tests/integrationTest/**', allowEmptyArchive: true
    }
}