// Pushes the images built in this run to Nexus. Credentials are injected, never written to the log.
def call() {
    withCredentials([usernamePassword(credentialsId: 'nexus-publisher',
                                      usernameVariable: 'NEXUS_USER',
                                      passwordVariable: 'NEXUS_PASSWORD')]) {
        env.CG_UNITS.split().each { u ->
            sh "ci/scripts/publish-image.sh ${u} ${env.CG_IMAGE_TAG}"
        }
    }
}
