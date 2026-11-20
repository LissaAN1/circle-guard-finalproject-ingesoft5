// Blocks the pipeline on CRITICAL image vulnerabilities or IaC misconfigurations.
def call(Map cfg = [:]) {
    String mode = cfg.mode?.toString()?.trim()
    if (!(mode in ['iac', 'images', 'secrets'])) {
        error('cgTrivy: mode must be iac, images or secrets')
    }
    sh(label: "trivy-${mode}", script: "bash ci/scripts/trivy-run.sh ${mode}")
}
