"""Offline contracts for secret scanning, least-privilege RBAC and Ingress TLS.

The tests never connect to AWS, Jenkins, Docker or a Kubernetes cluster.
"""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
BASH = shutil.which('bash')


def bash_path(path):
    """Convert Windows paths for subprocess calls running inside Git Bash."""
    if os.name != 'nt':
        return str(path)
    cygpath = shutil.which('cygpath')
    if not cygpath:
        raise RuntimeError('Git Bash cygpath is required on Windows')
    return subprocess.check_output([cygpath, '-u', str(path)], text=True).strip()


class SecretScanContract(unittest.TestCase):
    def test_secret_gate_runs_on_every_branch_before_build(self):
        code = (ROOT / 'ci/shared-library/vars/circleguardPipeline.groovy').read_text()
        self.assertLess(code.index("stage('Checkout')"), code.index("stage('Trivy Secrets')"))
        self.assertLess(code.index("stage('Trivy Secrets')"), code.index("stage('Build')"))
        section = code.split("stage('Trivy Secrets')", 1)[1].split("stage('Detect changes')", 1)[0]
        self.assertIn("cgTrivy(mode: 'secrets')", section)
        self.assertNotIn('when {', section)
        runner = (ROOT / 'ci/scripts/trivy-run.sh').read_text()
        self.assertIn('--scanners secret --exit-code 1', runner)
        self.assertIn('rm -f -- "$report"', runner)
        self.assertNotIn('ci/reports/trivy/secrets.json', runner)

    @unittest.skipUnless(BASH, 'Bash is not installed')
    def test_scanner_failure_blocks_release_without_printing_a_match(self):
        with tempfile.TemporaryDirectory(prefix='cg-secret-scan-') as temp:
            root = Path(temp)
            scripts = root / 'ci/scripts'
            scripts.mkdir(parents=True)
            shutil.copy2(ROOT / 'ci/scripts/trivy-run.sh', scripts / 'trivy-run.sh')
            mock_bin = root / 'mock-bin'
            mock_bin.mkdir()
            fake = mock_bin / 'docker'
            fake.write_text("""#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$MOCK_DOCKER_LOG"
exit "${MOCK_EXIT:-0}"
""")
            fake.chmod(0o755)
            log = root / 'docker.log'
            env = dict(os.environ, PATH=f'{bash_path(mock_bin)}:{os.environ.get("PATH", "")}',
                       MOCK_DOCKER_LOG=bash_path(log), CG_AGENT_CONTAINER='test-agent',
                       MOCK_EXIT='23')
            result = subprocess.run([BASH, bash_path(scripts / 'trivy-run.sh'), 'secrets'],
                                    cwd=root, env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('--scanners secret --exit-code 1', log.read_text())
            self.assertNotIn('password123', result.stdout + result.stderr)


class RbacContract(unittest.TestCase):
    @staticmethod
    def manifest(name):
        path = ROOT / 'infra/k8s/rbac' / name
        return {d['kind']: d for d in yaml.safe_load_all(path.read_text()) if d}

    def test_deployer_lacks_interactive_access(self):
        resources = self.manifest('jenkins-deployer.yaml')['Role']['rules']
        flat = {r for rule in resources for r in rule['resources']}
        self.assertNotIn('pods/exec', flat)
        self.assertNotIn('pods/portforward', flat)
        secret_rules = [r for r in resources if 'secrets' in r['resources']]
        self.assertEqual(len(secret_rules), 1)
        self.assertEqual(secret_rules[0]['resourceNames'], ['circleguard-secrets'])
        self.assertNotIn('create', secret_rules[0]['verbs'])
        self.assertNotIn('list', secret_rules[0]['verbs'])

    def test_e2e_cannot_deploy_or_read_secrets(self):
        doc = self.manifest('jenkins-e2e.yaml')
        self.assertEqual(doc['ServiceAccount']['metadata']['name'], 'jenkins-e2e')
        resources = {r for rule in doc['Role']['rules'] for r in rule['resources']}
        self.assertIn('pods/exec', resources)
        self.assertIn('pods/portforward', resources)
        self.assertIn('statefulsets', resources)
        self.assertNotIn('secrets', resources)
        self.assertNotIn('deployments', resources)
        self.assertNotIn('namespaces', resources)

    def test_jenkins_separates_deployment_from_e2e_credentials(self):
        base = yaml.safe_load((ROOT / 'infra/bootstrap/jenkins/casc.yaml').read_text())
        entries = base['jenkins']['authorizationStrategy']['globalMatrix']['entries']
        teacher = next(e['user']['permissions'] for e in entries if e['user']['name'] == '${JENKINS_TEACHER_USER}')
        admin = next(e['user']['permissions'] for e in entries if e['user']['name'] == '${JENKINS_ADMIN_USER}')
        self.assertEqual(set(teacher), {'Overall/Read', 'Job/Read', 'View/Read'})
        self.assertEqual(admin, ['Overall/Administer'])
        deploy = (ROOT / 'ci/shared-library/vars/cgK8sDeploy.groovy').read_text()
        e2e = (ROOT / 'ci/shared-library/vars/cgK8sE2E.groovy').read_text()
        self.assertIn('kubeconfig-${target}', deploy)
        self.assertIn('kubeconfig-e2e-${target}', e2e)
        self.assertNotIn('kubeconfig-e2e-${target}', deploy)
        provision = (ROOT / 'infra/k8s/rbac/provision-kubeconfig.sh').read_text()
        self.assertIn('jenkins-e2e.yaml', provision)


class IngressTlsContract(unittest.TestCase):
    def test_every_environment_requires_tls_on_both_ingresses(self):
        for env in ('dev', 'stage', 'prod'):
            with self.subTest(environment=env):
                file = ROOT / f'infra/k8s/overlays/{env}/kustomization.yaml'
                overlay = yaml.safe_load(file.read_text())
                for ingress in ('circleguard-web', 'circleguard-gateway'):
                    patches = [p for p in overlay['patches']
                               if p.get('target', {}).get('kind') == 'Ingress'
                               and p['target'].get('name') == ingress]
                    tls_patches = [patch for patch in patches if '/spec/tls' in patch['patch']]
                    self.assertEqual(len(tls_patches), 1)
                    ops = yaml.safe_load(tls_patches[0]['patch'])
                    values = {op['path']: op['value'] for op in ops}
                    self.assertEqual(values['/metadata/annotations/traefik.ingress.kubernetes.io~1router.entrypoints'], 'websecure')
                    self.assertEqual(values['/spec/rules/0/host'], f'{env}.circleguard.test')
                    self.assertEqual(values['/spec/tls'][0]['secretName'], 'circleguard-ingress-tls')
                    self.assertEqual(values['/spec/tls'][0]['hosts'], [f'{env}.circleguard.test'])

    def test_no_tls_private_material_is_committed_as_a_manifest(self):
        ignore = (ROOT / '.gitignore').read_text()
        self.assertIn('infra/k8s/tls/.private/', ignore)
        issue = (ROOT / 'infra/k8s/tls/issue-certificates.sh').read_text()
        apply = (ROOT / 'infra/k8s/tls/apply-certificates.sh').read_text()
        self.assertIn('-verify_hostname', issue)
        self.assertIn('circleguard-ingress-tls', apply)
        self.assertIn('create secret tls', apply)
        for env in ('dev', 'stage', 'prod'):
            overlay = yaml.safe_load((ROOT / f'infra/k8s/overlays/{env}/kustomization.yaml').read_text())
            self.assertNotIn('secretGenerator', overlay)


if __name__ == '__main__':
    unittest.main()


class TrivyIgnoreContract(unittest.TestCase):
    """The accepted-findings file must stay narrow and time-boxed."""

    def entries(self):
        lines = (ROOT / '.trivyignore').read_text(encoding='utf8').splitlines()
        return [l.strip() for l in lines if l.strip() and not l.lstrip().startswith('#')]

    def test_only_the_two_documented_spring_webmvc_cves_are_ignored(self):
        ids = sorted(e.split()[0] for e in self.entries())
        self.assertEqual(ids, ['CVE-2026-47884', 'CVE-2026-47890'])

    def test_every_exception_expires(self):
        for entry in self.entries():
            self.assertRegex(entry, r' exp:\d{4}-\d{2}-\d{2}$')

    def test_only_image_scan_uses_the_ignore_file(self):
        runner = (ROOT / 'ci/scripts/trivy-run.sh').read_text(encoding='utf8')
        self.assertEqual(runner.count('--ignorefile'), 1)
        self.assertIn('--ignorefile "$PWD/.trivyignore"', runner.split('elif [[ "$mode" == images ]]')[1].split('else')[0])
        self.assertIn('--severity CRITICAL --exit-code 1', runner)
