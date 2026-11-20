// HU-04/HU-05/HU-06/HU-07/HU-08: multibranch CI pipeline for the 8 services and the web client.
// Original stages: checkout, detect changes, build, test (+coverage), integration test,
//                  analysis (SonarQube), package, publish, deploy dev, E2E on DEV
//                  (blocks promotion), deploy stage + E2E + approve + deploy prod
//                  (main branch only).
// Multibranch CI/CD with an opt-in Kubernetes release path.
// Legacy Compose remains the default. Kubernetes releases build one image
// set, scan it, and promote the same immutable tag through three clusters.
def call() {
    pipeline {
        agent { label 'docker' }

        options {
            timestamps()
            // Avoid concurrent releases of the same branch.
            disableConcurrentBuilds()
            timeout(time: 240, unit: 'MINUTES')
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
            // HU-13: validate Kubernetes prerequisites before building or deploying.
            stage('Kubernetes Preflight') {
                when { expression { env.CG_CD_PLATFORM == 'k8s' } }
                steps { cgK8sPreflight() }
            }
            // HU-13: block the Kubernetes release on CRITICAL Terraform findings.
            stage('Trivy IaC') {
                when { expression { env.CG_CD_PLATFORM == 'k8s' } }
                steps { cgTrivy(mode: 'iac') }
            }
            stage('Build') {
                when { expression { cgHasUnits('service') } }
                steps { cgBuild() }
            }
            stage('Test') {
                when { expression { cgHasUnits('service') } }
                steps { cgTest() }
            }
            stage('Integration Test') {
                when {
                    expression {
                        cgHasUnits('service') && env.CG_INTEGRATION_ENABLED != 'false'
                    }
                }
                steps { cgIntegrationTest() }
            }
            stage('Analysis') {
                when { expression { env.SONAR_HOST_URL && cgHasUnits('service') } }
                steps { cgAnalysis() }
            }
            stage('Package') {
                when { expression { cgHasUnits('service') || cgHasUnits('client') } }
                steps { cgPackage() }
            }
            // HU-13: scan locally built images before publishing to Nexus.
            stage('Trivy Images') {
                when {
                    allOf {
                        expression { env.CG_CD_PLATFORM == 'k8s' }
                        expression { cgHasUnits('service') || cgHasUnits('client') }
                    }
                }
                steps { cgTrivy(mode: 'images') }
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
            // HU-13: Terraform applies only on integration branches with Kubernetes enabled.
            // DEV is the candidate validation environment of the same main build
            // before that immutable release is promoted to STAGE and PROD.
            stage('Terraform Plan DEV') {
                when {
                    allOf {
                        expression { env.CG_CD_PLATFORM == 'k8s' }
                        expression { env.BRANCH_NAME in ['dev', 'main'] }
                        expression { !env.CHANGE_ID }
                        expression { env.CG_IMAGE_TAG?.trim() as Boolean }
                        expression { env.NEXUS_REGISTRY?.trim() as Boolean }
                    }
                }
                steps { cgTerraform(environment: 'dev', action: 'plan') }
            }
            stage('Terraform Apply DEV') {
                when {
                    allOf {
                        expression { env.CG_CD_PLATFORM == 'k8s' }
                        expression { env.BRANCH_NAME in ['dev', 'main'] }
                        expression { !env.CHANGE_ID }
                        expression { env.CG_IMAGE_TAG?.trim() as Boolean }
                        expression { env.NEXUS_REGISTRY?.trim() as Boolean }
                    }
                }
                steps { cgTerraform(environment: 'dev', action: 'apply') }
            }
            stage('Deploy Dev') {
                when {
                    allOf {
                        expression { env.BRANCH_NAME == 'dev' || (env.BRANCH_NAME == 'main' && env.CG_CD_PLATFORM == 'k8s') }
                        expression { !env.CHANGE_ID }
                        expression { env.CG_IMAGE_TAG?.trim() as Boolean }
                        expression { env.NEXUS_REGISTRY?.trim() as Boolean }
                    }
                }
                steps {
                    script {
                        if (env.CG_CD_PLATFORM == 'k8s') {
                            cgK8sDeploy(environment: 'dev')
                        } else {
                            cgDeploy(environment: 'dev', appVersion: env.CG_IMAGE_TAG)
                        }
                    }
                }
            }
            // HU-07: E2E runs AFTER Deploy Dev so it validates the candidate already on the server.
            // A failure here blocks promotion to stage and prod.
            // HU-13: main also validates the K3s DEV candidate before promotion.
            stage('E2E on DEV') {
                when {
                    expression {
                        (env.BRANCH_NAME == 'dev' ||
                         (env.BRANCH_NAME == 'main' && env.CG_CD_PLATFORM == 'k8s')) &&
                        !env.CHANGE_ID
                    }
                }
                steps { cgE2E(environment: 'dev') }
            }

            stage('Terraform Plan STAGE') {
                when {
                    allOf {
                        expression { env.CG_CD_PLATFORM == 'k8s' }
                        expression { env.BRANCH_NAME == 'main' }
                        expression { !env.CHANGE_ID }
                        expression { env.NEXUS_REGISTRY?.trim() as Boolean }
                    }
                }
                steps { cgTerraform(environment: 'stage', action: 'plan') }
            }
            stage('Terraform Apply STAGE') {
                when {
                    allOf {
                        expression { env.CG_CD_PLATFORM == 'k8s' }
                        expression { env.BRANCH_NAME == 'main' }
                        expression { !env.CHANGE_ID }
                        expression { env.NEXUS_REGISTRY?.trim() as Boolean }
                    }
                }
                steps { cgTerraform(environment: 'stage', action: 'apply') }
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
                    script {
                        if (env.CG_CD_PLATFORM == 'k8s') {
                            cgK8sDeploy(environment: 'stage')
                        } else {
                            cgDeploy(environment: 'stage', appVersion: env.CG_IMAGE_TAG)
                        }
                    }
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
                steps { cgE2E(environment: 'stage') }
            }
            // HU-21: performance (Locust) and security (ZAP baseline) on the same stage release.
            // Both need the K3s cluster, so they run only on the Kubernetes release path.
            stage('Performance STAGE') {
                when {
                    allOf {
                        expression { env.CG_CD_PLATFORM == 'k8s' }
                        expression { env.BRANCH_NAME == 'main' }
                        expression { !env.CHANGE_ID }
                        expression { env.NEXUS_REGISTRY?.trim() as Boolean }
                    }
                }
                steps { cgPerformance(environment: 'stage') }
            }
            stage('ZAP Baseline STAGE') {
                when {
                    allOf {
                        expression { env.CG_CD_PLATFORM == 'k8s' }
                        expression { env.BRANCH_NAME == 'main' }
                        expression { !env.CHANGE_ID }
                        expression { env.NEXUS_REGISTRY?.trim() as Boolean }
                    }
                }
                steps { cgZap(environment: 'stage') }
            }
            // HU-13: plan PROD before the approval gate; apply that same plan afterward.
            stage('Terraform Plan PROD') {
                when {
                    allOf {
                        expression { env.CG_CD_PLATFORM == 'k8s' }
                        expression { env.BRANCH_NAME == 'main' }
                        expression { !env.CHANGE_ID }
                        expression { env.NEXUS_REGISTRY?.trim() as Boolean }
                        expression { env.CG_ENABLE_PROD_RELEASE == 'true' }
                    }
                }
                steps { cgTerraform(environment: 'prod', action: 'plan') }
            }
            stage('Approve Prod') {
                when {
                    allOf {
                        expression { env.BRANCH_NAME == 'main' }
                        expression { !env.CHANGE_ID }
                        expression { env.NEXUS_REGISTRY?.trim() as Boolean }
                        expression { env.CG_ENABLE_PROD_RELEASE == 'true' }
                    }
                }
                steps { script { cgApproveProd() } }
            }
            stage('Terraform Apply PROD') {
                when {
                    allOf {
                        expression { env.CG_CD_PLATFORM == 'k8s' }
                        expression { env.BRANCH_NAME == 'main' }
                        expression { !env.CHANGE_ID }
                        expression { env.NEXUS_REGISTRY?.trim() as Boolean }
                        expression { env.CG_ENABLE_PROD_RELEASE == 'true' }
                    }
                }
                steps { cgTerraform(environment: 'prod', action: 'apply') }
            }
            stage('Deploy Prod') {
                when {
                    allOf {
                        expression { env.BRANCH_NAME == 'main' }
                        expression { !env.CHANGE_ID }
                        expression { env.CG_IMAGE_TAG?.trim() as Boolean }
                        expression { env.NEXUS_REGISTRY?.trim() as Boolean }
                        expression { env.CG_ENABLE_PROD_RELEASE == 'true' }
                    }
                }
                steps {
                    script {
                        if (env.CG_CD_PLATFORM == 'k8s') {
                            cgK8sDeploy(environment: 'prod')
                        } else {
                            cgDeploy(environment: 'prod', appVersion: env.CG_IMAGE_TAG)
                        }
                    }
                }
            }
        }
        post {
            // HU-13: notify unsuccessful builds and archive Trivy reports before cleanup.
            unsuccessful {
                script { cgNotifyFailure() }
            }
            always {
                archiveArtifacts artifacts: 'ci/reports/trivy/*.json',
                    allowEmptyArchive: true, fingerprint: false
                sh 'docker image prune -f --filter "until=24h" || true'
            }
            success {
                echo "Pipeline OK. Units: ${env.CG_UNITS ?: '(none changed)'}"
            }
            cleanup {
                cleanWs(notFailBuild: true)
            }
        }
    }
}
