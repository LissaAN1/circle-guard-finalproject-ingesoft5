// Fail closed when Jenkins is configured for Kubernetes but required gates
// or shared image registry data are missing. Never silently fall back to Compose.
def call() {
    if (env.CG_CD_PLATFORM != 'k8s') {
        return
    }

    if (!env.NEXUS_REGISTRY?.trim()) {
        error('K3s preflight: NEXUS_REGISTRY must be configured')
    }

    if (!env.NOTIFY_WEBHOOK_URL?.startsWith('https://')) {
        error('K3s preflight: HTTPS failure webhook must be configured')
    }

    if (!env.SONAR_HOST_URL?.trim()) {
        error('K3s preflight: SonarQube gate must remain enabled')
    }

    if (env.CG_INTEGRATION_ENABLED == 'false') {
        error('K3s preflight: integration tests may not be disabled')
    }

    if (!env.CHANGE_ID && env.BRANCH_NAME in ['dev', 'main']) {
        List<String> units = env.CG_UNITS?.tokenize(' ') ?: []

        if (units.size() != 9 || units.toSet().size() != 9) {
            error('K3s preflight: complete nine-image release required')
        }
    }

    echo 'K3s preflight complete: Nexus, notification and quality gates configured'
}
