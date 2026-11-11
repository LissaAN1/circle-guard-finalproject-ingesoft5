// Images are published only from dev and main, and only when a Nexus registry is configured.
def call() {
    if (!env.NEXUS_REGISTRY?.trim()) {
        echo 'Publish skipped: NEXUS_REGISTRY is not configured on this Jenkins.'
        return false
    }
    return !env.CHANGE_ID && (env.BRANCH_NAME in ['dev', 'main'])
}
