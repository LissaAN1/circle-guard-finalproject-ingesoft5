// Creates the namespace's Secret and applies the immutable release to K3s.
def call(Map cfg = [:]) {
    String target = cfg.environment?.toString()?.trim()

    if (!(target in ['dev', 'stage', 'prod'])) {
        error('cgK8sDeploy: environment must be dev, stage or prod')
    }

    if (!env.CG_IMAGE_TAG?.trim() || !env.NEXUS_REGISTRY?.trim()) {
        error('cgK8sDeploy: release tag and Nexus registry are mandatory')
    }

    withCredentials([
        file(credentialsId: "kubeconfig-${target}", variable: 'KUBECONFIG'),
        file(credentialsId: "k8s-app-env-${target}", variable: 'APP_ENV_FILE')
    ]) {
        sh(
            label: "k8s-deploy-${target}",
            script: "bash ci/scripts/k8s-run.sh ${target}"
        )
    }
}
