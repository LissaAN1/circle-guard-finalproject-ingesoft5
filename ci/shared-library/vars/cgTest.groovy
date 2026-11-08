// Runs unit tests of the changed services and publishes the JUnit report.
//   tests=enforce : a failing test fails the build
//   tests=report  : a failing test only marks the build UNSTABLE (documented baseline failure)
def call() {
    List<String> enforce = []
    List<String> report = []
    (env.CG_SERVICES.split() as List<String>).each { u ->
        String mode = sh(script: "ci/scripts/unit-info.sh ${u} tests", returnStdout: true).trim()
        if (mode == 'enforce') { enforce << u } else if (mode == 'report') { report << u }
    }

    if (report) {
        int rc = cgGradle(report, 'test', true)
        if (rc != 0) {
            unstable("Known failing tests in: ${report.join(', ')} (see docs/operaciones/hallazgos_tecnicos.md)")
        }
    }
    try {
        if (enforce) {
            cgGradle(enforce, 'test')
        }
    } finally {
        junit testResults: '**/build/test-results/test/*.xml', allowEmptyResults: true
    }
}
