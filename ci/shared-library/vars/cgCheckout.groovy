// Checks out the commit and makes the comparison branch available for change detection.
def call() {
    checkout scm
    env.CG_SHA7 = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()

    if (env.CHANGE_TARGET) {
        // Pull request: compare against its target branch.
        sh 'git fetch --no-tags origin "+refs/heads/${CHANGE_TARGET}:refs/remotes/origin/${CHANGE_TARGET}"'
    } else if (env.BRANCH_NAME != 'dev') {
        sh 'git fetch --no-tags origin "+refs/heads/dev:refs/remotes/origin/dev" || true'
    }
}
