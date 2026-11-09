// Pushes the images built in this run to Nexus. Credentials are injected, never written to the log.
// If 'nexus-publisher' is not yet configured in Jenkins the stage is skipped without failing the build.
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
            echo 'Publish skipped: nexus-publisher credential not found in Jenkins. Run ci-remote.sh with NEXUS_PUBLISHER_PASSWORD to enable.'
            return
        }
        throw e
    }
}
