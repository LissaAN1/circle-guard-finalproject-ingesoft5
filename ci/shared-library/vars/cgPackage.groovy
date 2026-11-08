// Builds one Docker image per changed unit with an immutable tag: <semver>-ci.<build>.<sha7> (never "latest").
def call() {
    String semver = sh(script: 'infra/release/version.sh', returnStdout: true).trim()
    env.CG_IMAGE_TAG = "${semver}-ci.${env.BUILD_NUMBER}.${env.CG_SHA7}"
    echo "Image tag: ${env.CG_IMAGE_TAG}"
    env.CG_UNITS.split().each { u ->
        sh "ci/scripts/package-image.sh ${u} ${env.CG_IMAGE_TAG}"
    }
}
