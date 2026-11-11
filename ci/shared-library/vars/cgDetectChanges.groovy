// Decides which units (services / web client) this build must process.
// The rules live in ci/scripts/changed-units.sh (unit-tested); root changes select every unit.
def call() {
    String base
    if (env.CHANGE_TARGET) {
        base = "origin/${env.CHANGE_TARGET}"
    } else if (env.GIT_PREVIOUS_SUCCESSFUL_COMMIT) {
        base = env.GIT_PREVIOUS_SUCCESSFUL_COMMIT
    } else if (env.BRANCH_NAME in ['dev', 'main']) {
        base = 'HEAD~1'
    } else {
        base = 'origin/dev'
    }

    boolean fullRelease = env.BRANCH_NAME == 'main' && !env.CHANGE_ID
    String forceAll = fullRelease ? 'true' : (env.FORCE_ALL ?: 'false')

    String out = withEnv([
        "CG_BASE=${base}",
        "FORCE_ALL=${forceAll}"
    ]) {
        sh(
            script: 'ci/scripts/changed-units.sh "$CG_BASE"',
            returnStdout: true
        ).trim()
    }

    if (fullRelease) {
        echo 'Release main: processing all units'
    }

    List<String> units = out ? out.split('\n').collect { it.trim() }.findAll { it } : []

    List<String> services = []
    List<String> clients = []
    units.each { u ->
        String kind = sh(script: "ci/scripts/unit-info.sh ${u} kind", returnStdout: true).trim()
        (kind == 'service' ? services : clients) << u
    }

    env.CG_UNITS = units.join(' ')
    env.CG_SERVICES = services.join(' ')
    env.CG_CLIENTS = clients.join(' ')
    echo "Base: ${base}"
    echo "Units to process: ${units ? units.join(', ') : 'none (no buildable change)'}"
}
