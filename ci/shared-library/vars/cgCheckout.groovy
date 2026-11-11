// Checks out the commit and makes the comparison branch available for change detection.
def call() {
    // Pipeline steps do not export GIT_COMMIT by themselves; cgNotify needs it for the commit status.
    def scmVars = checkout scm
    env.GIT_COMMIT = scmVars.GIT_COMMIT ?: sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
    env.CG_SHA7 = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()

    if (env.CHANGE_TARGET) {
        // Pull request: compare against its target branch.
        sh 'git fetch --no-tags origin "+refs/heads/${CHANGE_TARGET}:refs/remotes/origin/${CHANGE_TARGET}"'
    } else if (env.BRANCH_NAME != 'dev') {
        sh 'git fetch --no-tags origin "+refs/heads/dev:refs/remotes/origin/dev" || true'
    }
}
