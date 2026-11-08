// HU-04/HU-07/HU-09: multibranch CI pipeline for the 8 services and the web client.
// Stages: checkout, detect changes, build, test, E2E (dev), analysis, package, publish.
// Failure/unstable builds trigger cgNotify (GitHub commit status + optional webhook).
def call() {
    pipeline {
        agent { label 'docker' }

        options {
            timestamps()
            timeout(time: 90, unit: 'MINUTES')
            buildDiscarder(logRotator(numToKeepStr: '15'))
            skipDefaultCheckout(true)
        }

        stages {
            stage('Checkout') {
                steps { cgCheckout() }
            }
            stage('Detect changes') {
                steps { cgDetectChanges() }
            }
            stage('Build') {
                when { expression { cgHasUnits('service') } }
                steps { cgBuild() }
            }
            stage('Test') {
                when { expression { cgHasUnits('service') } }
                steps { cgTest() }
            }
            stage('E2E on DEV') {
                when { expression { env.BRANCH_NAME == 'dev' } }
                steps { cgE2E() }
            }
            stage('Analysis') {
                when { expression { env.ENABLE_SONAR == 'true' && cgHasUnits('service') } }
                steps { cgAnalysis() }
            }
            stage('Package') {
                when { expression { cgHasUnits('service') || cgHasUnits('client') } }
                steps { cgPackage() }
            }
            stage('Publish') {
                when {
                    allOf {
                        expression { cgHasUnits('service') || cgHasUnits('client') }
                        expression { cgShouldPublish() }
                    }
                }
                steps { cgPublish() }
            }
        }

        post {
            always {
                script {
                    // HU-09: notify before workspace is wiped so cgNotify can still run sh steps.
                    if (currentBuild.currentResult in ['FAILURE', 'UNSTABLE']) {
                        cgNotify(currentBuild.currentResult)
                    }
                }
                sh 'docker image prune -f --filter "until=24h" || true'
                cleanWs(notFailBuild: true)
            }
            success {
                echo "Pipeline OK. Units: ${env.CG_UNITS ?: '(none changed)'}"
            }
        }
    }
}
