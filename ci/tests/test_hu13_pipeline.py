"""Offline integration contracts for Terraform, Trivy and K3s release automation.

The tests use mock executables; they never contact Jenkins, AWS, Docker or K3s.
"""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VARS = ROOT / 'ci/shared-library/vars'
BASH = shutil.which('bash')


def bash_path(path):
    """Translate Windows file paths when subprocess uses Git Bash."""
    if os.name != 'nt':
        return str(path)
    cygpath = shutil.which('cygpath')
    if not cygpath:
        raise RuntimeError('Git Bash cygpath is required on Windows')
    return subprocess.check_output([cygpath, '-u', str(path)], text=True).strip()


class Hu13PipelineContract(unittest.TestCase):
    def test_terraform_and_kubectl_entrypoints_exist(self):
        terraform = (VARS / 'cgTerraform.groovy').read_text(encoding='utf8')
        kubectl = (ROOT / 'ci/scripts/kubectl').read_text(encoding='utf8')
        deploy = (ROOT / 'ci/scripts/k8s-run.sh').read_text(encoding='utf8')

        self.assertIn('ci/scripts/terraform-run.sh', terraform)
        self.assertTrue((ROOT / 'ci/scripts/terraform-run.sh').is_file())

        self.assertIn('exec bash "$HERE/kubectl-run.sh" "$@"', kubectl)
        self.assertTrue((ROOT / 'ci/scripts/kubectl-run.sh').is_file())

        self.assertIn('export PATH="$ROOT/ci/scripts:$PATH"', deploy)

    def test_progressive_release_and_approval_order(self):
        code = (VARS / 'circleguardPipeline.groovy').read_text(encoding='utf8')
        ordered = [
            "stage('Kubernetes Preflight')", "stage('Trivy IaC')", "stage('Package')", "stage('Trivy Images')",
            "stage('Publish')", "stage('Terraform Plan DEV')",
            "stage('Terraform Apply DEV')", "stage('Deploy Dev')",
            "stage('E2E on DEV')", "stage('Terraform Plan STAGE')",
            "stage('Terraform Apply STAGE')", "stage('Deploy Stage')",
            "stage('E2E Tests')", "stage('Terraform Plan PROD')",
            "stage('Approve Prod')", "stage('Terraform Apply PROD')",
            "stage('Deploy Prod')",
        ]
        positions = [code.index(stage) for stage in ordered]
        self.assertEqual(positions, sorted(positions))
        self.assertIn("cgApproveProd()", code)
        self.assertIn("cgNotifyFailure()", code)
        self.assertIn("cgK8sPreflight()", code)
        self.assertIn("env.CG_CD_PLATFORM == 'k8s'", code)
        self.assertIn("cgDeploy(environment: 'dev', appVersion: env.CG_IMAGE_TAG)", code)
        self.assertIn("cgK8sDeploy(environment: 'dev')", code)
        self.assertIn("cgK8sDeploy(environment: 'stage')", code)
        self.assertIn("cgK8sDeploy(environment: 'prod')", code)

    def test_image_and_iac_scans_block_on_critical(self):
        src = (ROOT / 'ci/scripts/trivy-run.sh').read_text(encoding='utf8')
        self.assertIn('--severity CRITICAL --exit-code 1', src)
        self.assertIn('--image-src docker', src)
        self.assertIn('infra/terraform', src)
        self.assertIn('circleguard/${name}:${CG_IMAGE_TAG}', src)

    def test_release_build_includes_all_images_on_k8s_dev(self):
        src = (VARS / 'cgDetectChanges.groovy').read_text(encoding='utf8')
        self.assertIn("env.CG_CD_PLATFORM == 'k8s'", src)
        self.assertIn("env.BRANCH_NAME == 'dev'", src)
        self.assertIn("forceAll = 'true'", src)

    def test_terraform_applies_only_precomputed_plan(self):
        code = (ROOT / 'ci/scripts/terraform-run.sh').read_text(encoding='utf8')
        self.assertIn('[[ -s "$plan" ]]', code)
        self.assertIn('apply -input=false -lock-timeout=5m terraform.tfplan', code)
        self.assertIn('-backend-config="$TF_BACKEND_FILE"', code)
        self.assertIn('-var-file="$TF_VARS_FILE"', code)

    def test_k8s_credentials_and_e2e_are_separate(self):
        code = (VARS / 'cgK8sDeploy.groovy').read_text(encoding='utf8')
        self.assertIn('kubeconfig-${target}', code)
        self.assertIn('k8s-app-env-${target}', code)
        self.assertIn('k8s-run.sh', code)
        e2e = (VARS / 'cgK8sE2E.groovy').read_text(encoding='utf8')
        self.assertIn('run-k8s.sh', e2e)
        self.assertIn('E2E failed', e2e)
        self.assertIn('junit testResults:', e2e)


@unittest.skipUnless(BASH, 'Bash is not installed')
class Hu13ScriptSimulation(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='hu13-offline-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.script_dir = self.root / 'ci/scripts'
        self.script_dir.mkdir(parents=True)
        for src in ('terraform-run.sh', 'trivy-run.sh', 'unit-info.sh'):
            shutil.copy2(ROOT / 'ci/scripts' / src, self.script_dir / src)
        (self.root / 'ci/units.conf').write_text('auth service enforce gate\n')
        self.bin = self.root / 'mock-bin'
        self.bin.mkdir()
        self.log = self.root / 'docker.log'
        fake = self.bin / 'docker'
        fake.write_text('''#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "$MOCK_DOCKER_LOG"
case " $* " in
  *" plan "*) mkdir -p infra/terraform/environments/dev; printf 'mockplan' > infra/terraform/environments/dev/terraform.tfplan;;
esac
if [[ "${MOCK_DOCKER_FAIL:-0}" == 1 ]]; then exit 41; fi
''')
        fake.chmod(0o755)
        target = self.root / 'infra/terraform/environments/dev'
        target.mkdir(parents=True)
        (target / 'versions.tf').write_text('terraform { backend "s3" {} }\n')
        self.backend = self.root / 'backend.hcl'; self.backend.write_text('bucket = "mock"\n')
        self.vars = self.root / 'terraform.tfvars'; self.vars.write_text('region = "us-east-1"\n')
        self.env = dict(os.environ, PATH=f'{bash_path(self.bin)}:/usr/bin:/bin',
                        MOCK_DOCKER_LOG=bash_path(self.log),
                        TF_BACKEND_FILE=bash_path(self.backend), TF_VARS_FILE=bash_path(self.vars),
                        AWS_ACCESS_KEY_ID='mock', AWS_SECRET_ACCESS_KEY='mock',
                        AWS_DEFAULT_REGION='us-east-1')

    def run_script(self, script, *args, overrides=None):
        env = dict(self.env, **(overrides or {}))
        return subprocess.run([BASH, bash_path(self.script_dir / script), *args],
                              cwd=self.root, env=env, text=True,
                              capture_output=True)

    def test_plan_then_apply_never_apply_without_plan(self):
        initial = self.run_script('terraform-run.sh', 'dev', 'apply')
        self.assertNotEqual(initial.returncode, 0)
        self.assertIn('Missing approved plan', initial.stderr)
        plan = self.run_script('terraform-run.sh', 'dev', 'plan')
        self.assertEqual(plan.returncode, 0, plan.stderr)
        apply = self.run_script('terraform-run.sh', 'dev', 'apply')
        self.assertEqual(apply.returncode, 0, apply.stderr)
        self.assertFalse((self.root / 'infra/terraform/environments/dev/terraform.tfplan').exists())
        self.assertIn('terraform.tfplan', self.log.read_text())

    def test_terraform_error_blocks_release(self):
        result = self.run_script('terraform-run.sh', 'dev', 'plan',
                                 overrides={'MOCK_DOCKER_FAIL': '1'})
        self.assertNotEqual(result.returncode, 0)

    def test_trivy_critical_or_scanner_error_blocks_release(self):
        result = self.run_script('trivy-run.sh', 'iac',
                                 overrides={'MOCK_DOCKER_FAIL': '1'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('--severity CRITICAL --exit-code 1', self.log.read_text())

    def test_wrong_terraform_environment_is_rejected(self):
        result = self.run_script('terraform-run.sh', 'production', 'apply')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.log.read_text() if self.log.exists() else '', '')


@unittest.skipUnless(BASH, 'Bash is not installed')
class Hu13KubernetesSimulation(unittest.TestCase):
    """Execute the actual deploy wrapper against a fake Kubernetes CLI."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='hu13-k8s-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        shutil.copytree(ROOT / 'infra/k8s', self.root / 'infra/k8s')
        scripts = self.root / 'ci/scripts'
        scripts.mkdir(parents=True)
        shutil.copy2(ROOT / 'ci/scripts/k8s-run.sh', scripts / 'k8s-run.sh')
        fake = scripts / 'kubectl'
        fake.write_text('''#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "$MOCK_KUBECTL_LOG"
if [[ " $* " == *" config get-contexts -o name "* ]]; then
  echo circleguard-dev
elif [[ " $* " == *" create namespace "* ]]; then
  printf 'apiVersion: v1\\nkind: Namespace\\nmetadata: {name: circleguard-dev}\\n'
fi
if [[ " $* " == *" rollout status statefulset/kafka "* && "${MOCK_K8S_FAIL:-}" == kafka ]]; then
  exit 55
fi
''')
        fake.chmod(0o755)
        envdir = self.root / 'infra/environments'
        envdir.mkdir(parents=True)
        self.app_env = self.root / 'app.env'
        self.app_env.write_text(''.join(f'{k}=mock-value\n' for k in (
            'DB_USER', 'DB_PASSWORD', 'NEO4J_PASSWORD', 'LDAP_ADMIN_PASSWORD',
            'REDIS_PASSWORD', 'JWT_SECRET', 'QR_SECRET', 'VAULT_SECRET',
            'VAULT_SALT', 'VAULT_HASH_SALT')))
        self.kubeconfig = self.root / 'kubeconfig'
        self.kubeconfig.write_text('mock')
        self.log = self.root / 'kubectl.log'
        self.env = dict(os.environ, KUBECONFIG=bash_path(self.kubeconfig),
                        APP_ENV_FILE=bash_path(self.app_env),
                        NEXUS_REGISTRY='172.31.10.11:8082', CG_IMAGE_TAG='v1.2.3-ci.9.1234567',
                        MOCK_KUBECTL_LOG=bash_path(self.log))

    def run_k8s(self, **extra):
        return subprocess.run([BASH, bash_path(self.root / 'ci/scripts/k8s-run.sh'), 'dev'],
                              cwd=self.root, env=dict(self.env, **extra),
                              capture_output=True, text=True)

    def test_k8s_success_uses_target_context_and_cleans_private_file(self):
        result = self.run_k8s()
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self.log.read_text()
        self.assertIn('--context circleguard-dev', log)
        self.assertIn('rollout status deployment/web', log)
        self.assertFalse((self.root / 'infra/environments/.env.dev').exists())

    def test_kafka_rollout_error_aborts_and_cleans_secret_copy(self):
        result = self.run_k8s(MOCK_K8S_FAIL='kafka')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('rollout status deployment/web', self.log.read_text())
        self.assertFalse((self.root / 'infra/environments/.env.dev').exists())


if __name__ == '__main__':
    unittest.main()
