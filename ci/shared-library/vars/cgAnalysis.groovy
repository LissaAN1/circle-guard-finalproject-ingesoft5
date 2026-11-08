// Optional SonarQube analysis; disabled unless ENABLE_SONAR=true. The quality gate itself belongs to HU-05.
// Needs env SONAR_HOST_URL and a Jenkins "Secret text" credential with id sonar-token.
def call() {
    withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
        (env.CG_SERVICES.split() as List<String>).each { u ->
            String dir = sh(script: "ci/scripts/unit-info.sh ${u} dir", returnStdout: true).trim()
            // --volumes-from: the workspace lives in the agent container, not on the Docker host.
            sh """
                docker run --rm --volumes-from circleguard-build-agent -w "\$PWD" \\
                  -e SONAR_HOST_URL="\$SONAR_HOST_URL" -e SONAR_TOKEN \\
                  sonarsource/sonar-scanner-cli:11 \\
                  -Dsonar.projectKey=circleguard-${u} \\
                  -Dsonar.sources=${dir}/src/main \\
                  -Dsonar.java.binaries=${dir}/build/classes
            """
        }
    }
}
