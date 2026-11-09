// HU-05: SonarQube analysis with a BLOCKING quality gate.
// Runs for the changed units marked "quality=gate" in ci/units.conf. The scanner uploads the sources and
// the JaCoCo report, waits for the server verdict (sonar.qualitygate.wait) and exits non-zero when the
// gate fails, so the stage fails and Package/Publish never run.
// Needs env SONAR_HOST_URL (global property) and the Jenkins "Secret text" credential sonar-token.
def call() {
    List<String> gated = (env.CG_SERVICES.split() as List<String>).findAll { u ->
        sh(script: "ci/scripts/unit-info.sh ${u} quality", returnStdout: true).trim() == 'gate'
    }
    if (!gated) {
        echo 'Analysis: no changed unit is gated by SonarQube.'
        return
    }
    withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
        gated.each { u ->
            String dir = sh(script: "ci/scripts/unit-info.sh ${u} dir", returnStdout: true).trim()
            // --volumes-from: the workspace lives in the agent container, not on the Docker host.
            sh """
                docker run --rm --volumes-from circleguard-build-agent -w "\$PWD" \\
                  -u "\$(id -u):\$(id -g)" -e SONAR_USER_HOME=/tmp/.sonar \\
                  -e SONAR_HOST_URL="\$SONAR_HOST_URL" -e SONAR_TOKEN \\
                  sonarsource/sonar-scanner-cli:11 \\
                  -Dsonar.projectKey=circleguard-${u} \\
                  -Dsonar.sources=${dir}/src/main \\
                  -Dsonar.tests=${dir}/src/test \\
                  -Dsonar.java.binaries=${dir}/build/classes \\
                  -Dsonar.coverage.jacoco.xmlReportPaths=${dir}/build/reports/jacoco/test/jacocoTestReport.xml \\
                  -Dsonar.qualitygate.wait=true \\
                  -Dsonar.qualitygate.timeout=300
            """
        }
    }
}
