// Pushes the images built in this run to Nexus. Credentials are injected, never written to the log.
// If 'nexus-publisher' is not configured in Jenkins, publication fails.
def call() {
    try {
        withCredentials([usernamePassword(credentialsId: 'nexus-publisher',
                                          usernameVariable: 'NEXUS_USER',
                                          passwordVariable: 'NEXUS_PASSWORD')]) {
            env.CG_UNITS.split().each { u ->
                sh "ci/scripts/publish-image.sh ${u} ${env.CG_IMAGE_TAG}"
            }
        }
    } catch (hudson.AbortException e) {
        if (e.message?.contains('nexus-publisher')) {
            error(
                'Publish aborted: required Nexus credential ' +
                'nexus-publisher is unavailable'
            )
        }
        throw e
    }
}
