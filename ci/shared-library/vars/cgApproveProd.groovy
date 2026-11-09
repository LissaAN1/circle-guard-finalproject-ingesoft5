// HU-08: manual gate before deploying to prod.
// Times out after 30 minutes to avoid blocking executors indefinitely.
def call() {
    timeout(time: 30, unit: 'MINUTES') {
        input message: "Deploy ${env.CG_IMAGE_TAG ?: 'this build'} to prod?", ok: 'Approve'
    }
}
