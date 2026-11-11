// Runs the Gradle wrapper for a list of units with the given task (e.g. 'assemble', 'test').
// Returns the process exit code when returnStatus is true.
def call(List<String> units, String task, boolean returnStatus = false) {
    List<String> targets = units.collect { u ->
        sh(script: "ci/scripts/unit-info.sh ${u} gradle", returnStdout: true).trim() + ':' + task
    }
    String cmd = "./gradlew --no-daemon --console=plain --continue ${targets.join(' ')}"
    return sh(script: cmd, returnStatus: returnStatus)
}
