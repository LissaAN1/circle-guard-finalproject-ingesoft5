// Applies a previously reviewed Terraform plan for one isolated environment.
def call(Map cfg = [:]) {
    String target = cfg.environment?.toString()?.trim()
    String action = cfg.action?.toString()?.trim()
    if (!(target in ['dev', 'stage', 'prod']) || !(action in ['plan', 'apply'])) {
        error('cgTerraform: environment=dev|stage|prod and action=plan|apply are required')
    }
    String region = env.CG_AWS_REGION?.trim() ?: 'us-east-1'
    withCredentials([
        usernamePassword(credentialsId: 'aws-terraform',
            usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY'),
        file(credentialsId: "tf-backend-${target}", variable: 'TF_BACKEND_FILE'),
        file(credentialsId: "tf-vars-${target}", variable: 'TF_VARS_FILE')
    ]) {
        withEnv(["AWS_DEFAULT_REGION=${region}", "AWS_REGION=${region}"]) {
            sh(label: "terraform-${action}-${target}",
                script: "bash ci/scripts/terraform-run.sh ${target} ${action}")
        }
    }
}
