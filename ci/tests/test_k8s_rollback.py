"""HU-22: offline tests for infra/k8s/rollback.sh (no AWS or cluster needed)."""
import os
import re
import shutil
import subprocess
import tempfile
import unittest
import unittest.mock
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "infra" / "k8s" / "rollback.sh"
BASH = shutil.which("bash")


def bash_path(path):
    """Translate Windows file paths when subprocess uses Git Bash."""
    if os.name != "nt":
        return str(path)
    cygpath = shutil.which("cygpath")
    if not cygpath:
        raise RuntimeError("Git Bash cygpath is required on Windows")
    return subprocess.check_output([cygpath, "-u", str(path)], text=True).strip()


class RollbackContractTests(unittest.TestCase):
    def test_script_pins_cluster_and_uses_kc(self):
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("select_cluster", text)
        self.assertNotRegex(text, r"^\s*kubectl ")

    def test_docs_and_changelog_exist(self):
        self.assertTrue((ROOT / "CHANGELOG.md").is_file())
        self.assertTrue((ROOT / "docs/operaciones/hu-22-rollback-k8s.md").is_file())
        self.assertTrue((ROOT / "docs/operaciones/registro-cambios-ambientes.md").is_file())

    @unittest.skipUnless(BASH, "Bash is not installed")
    def test_script_syntax_is_valid(self):
        subprocess.run([BASH, "-n", str(SCRIPT)], check=True)


@unittest.skipUnless(BASH, "Bash is not installed")
class RollbackSimulationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="hu22-rollback-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        shutil.copytree(ROOT / "infra/k8s", self.root / "infra/k8s")
        self.bin = self.root / "mock-bin"
        self.bin.mkdir()
        self.log = self.root / "kubectl.log"
        fake = self.bin / "kubectl"
        fake.write_text(
            '#!/usr/bin/env bash\n'
            'set -euo pipefail\n'
            'printf "%s\\n" "$*" >> "$MOCK_KUBECTL_LOG"\n'
            'if [[ " $* " == *" config get-contexts -o name "* ]]; then\n'
            '  echo "${MOCK_CONTEXT:-circleguard-dev}"\n'
            'fi\n',
            encoding="utf-8",
            newline="\n",
        )
        fake.chmod(0o755)
        self.env = self.clean_env()

    def clean_env(self):
        """Caller environment without the variables that pick a cluster.

        rollback.sh honours KUBE_CONTEXT, so a developer shell that still exports
        KUBE_CONTEXT=circleguard-stage would make the dev simulation look for the
        wrong context. The tests must not depend on the shell that runs them.
        """
        env = {k: v for k, v in os.environ.items() if k not in ("KUBE_CONTEXT", "KUBECONFIG", "MOCK_CONTEXT")}
        env.update(PATH=f"{bash_path(self.bin)}:/usr/bin:/bin", MOCK_KUBECTL_LOG=bash_path(self.log))
        return env

    def run_rollback(self, *args, **extra):
        return subprocess.run(
            [BASH, bash_path(self.root / "infra/k8s/rollback.sh"), *args],
            cwd=self.root,
            env=dict(self.env, **extra),
            capture_output=True,
            text=True,
        )

    def test_rollback_to_previous_revision(self):
        res = self.run_rollback("dev", "auth")
        self.assertEqual(res.returncode, 0, res.stderr)
        log = self.log.read_text(encoding="utf-8")
        self.assertIn("--context circleguard-dev -n circleguard-dev rollout history deployment/auth", log)
        self.assertIn("--context circleguard-dev -n circleguard-dev rollout undo deployment/auth", log)
        self.assertIn("--context circleguard-dev -n circleguard-dev rollout status deployment/auth --timeout=300s", log)
        self.assertIn("get pods -l app.kubernetes.io/name=auth -o wide", log)

    def test_ignores_cluster_variables_exported_in_the_callers_shell(self):
        with unittest.mock.patch.dict(os.environ, {"KUBE_CONTEXT": "circleguard-stage", "KUBECONFIG": "/nonexistent"}):
            self.env = self.clean_env()
        res = self.run_rollback("dev", "auth")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("--context circleguard-dev -n circleguard-dev rollout undo deployment/auth",
                      self.log.read_text(encoding="utf-8"))

    def test_rollback_to_specific_revision(self):
        res = self.run_rollback("dev", "auth", "2")
        self.assertEqual(res.returncode, 0, res.stderr)
        log = self.log.read_text(encoding="utf-8")
        self.assertIn("rollout undo deployment/auth --to-revision=2", log)

    def test_rejects_invalid_environment_and_missing_service(self):
        self.assertEqual(self.run_rollback("production", "auth").returncode, 2)
        self.assertEqual(self.run_rollback("dev").returncode, 2)

    def test_rejects_context_of_another_environment(self):
        res = self.run_rollback("dev", "auth", MOCK_CONTEXT="circleguard-prod")
        self.assertNotEqual(res.returncode, 0)
        log = self.log.read_text(encoding="utf-8") if self.log.exists() else ""
        self.assertNotIn("rollout undo", log)


if __name__ == "__main__":
    unittest.main()