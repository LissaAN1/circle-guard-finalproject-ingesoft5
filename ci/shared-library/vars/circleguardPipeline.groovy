// HU-04/HU-05/HU-07/HU-08/HU-09: multibranch CI pipeline for the 8 services and the web client.
// Stages: checkout, detect changes, build, test (+coverage), E2E (dev), analysis (SonarQube quality gate), package,
//         publish, deploy dev (dev branch), deploy stage + E2E + approve + deploy prod (main branch).
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
                when { expression { env.SONAR_HOST_URL && cgHasUnits('service') } }
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

            // HU-08: continuous delivery stages — only run on integration branches, never on PRs.
            stage('Deploy Dev') {
                when {
                    allOf {
                        expression { env.BRANCH_NAME == 'dev' }
                        expression { !env.CHANGE_ID }
                        expression { env.CG_IMAGE_TAG?.trim() as Boolean }
                        expression { env.NEXUS_REGISTRY?.trim() as Boolean }
                    }
                }
                steps {
                    script { cgDeploy(environment: 'dev', appVersion: env.CG_IMAGE_TAG) }
                }
            }
            stage('Deploy Stage') {
                when {
                    allOf {
                        expression { env.BRANCH_NAME == 'main' }
                        expression { !env.CHANGE_ID }
                        expression { env.CG_IMAGE_TAG?.trim() as Boolean }
                        expression { env.NEXUS_REGISTRY?.trim() as Boolean }
                    }
                }
                steps {
                    script { cgDeploy(environment: 'stage', appVersion: env.CG_IMAGE_TAG) }
                }
            }
            stage('E2E Tests') {
                when {
                    allOf {
                        expression { env.BRANCH_NAME == 'main' }
                        expression { !env.CHANGE_ID }
                        expression { env.NEXUS_REGISTRY?.trim() as Boolean }
                    }
                }
                steps { cgE2E() }
            }
            stage('Approve Prod') {
                when {
                    allOf {
                        expression { env.BRANCH_NAME == 'main' }
                        expression { !env.CHANGE_ID }
                        expression { env.NEXUS_REGISTRY?.trim() as Boolean }
                    }
                }
                steps {
                    script { cgApproveProd() }
                }
            }
            stage('Deploy Prod') {
                when {
                    allOf {
                        expression { env.BRANCH_NAME == 'main' }
                        expression { !env.CHANGE_ID }
                        expression { env.CG_IMAGE_TAG?.trim() as Boolean }
                        expression { env.NEXUS_REGISTRY?.trim() as Boolean }
                    }
                }
                steps {
                    script { cgDeploy(environment: 'prod', appVersion: env.CG_IMAGE_TAG) }
                }
            }
            stage('Integration Test') {
                when { expression { cgHasUnits('service') } }
                steps { cgIntegrationTest() }
            }
        }

        post {
            always {
                sh 'docker image prune -f --filter "until=24h" || true'
                cleanWs(notFailBuild: true)
            }
            success {
                echo "Pipeline OK. Units: ${env.CG_UNITS ?: '(none changed)'}"
            }
        }
    }
}
