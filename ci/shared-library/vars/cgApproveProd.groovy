// HU-08: manual gate before deploying to prod.
// Times out after 30 minutes to avoid blocking executors indefinitely.
def call() {
    String approvers = env.CG_PROD_APPROVERS?.trim()

    if (!approvers) {
        error('cgApproveProd: CG_PROD_APPROVERS is required')
    }

    if (env.CG_ENABLE_PROD_RELEASE != 'true') {
        error('cgApproveProd: production release is disabled')
    }

    if (!env.CG_IMAGE_TAG?.trim()) {
        error('cgApproveProd: release image tag is required')
    }

    timeout(time: 30, unit: 'MINUTES') {
        input(
            message: "Deploy ${env.CG_IMAGE_TAG} to prod?",
            ok: 'Approve',
            submitter: approvers,
            submitterParameter: 'CG_PROD_APPROVED_BY'
        )
    }
}
