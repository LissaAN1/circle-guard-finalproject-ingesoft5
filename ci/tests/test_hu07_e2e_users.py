"""HU-07: offline tests for tests/e2e-playwright/scripts/ensure-e2e-users.sh (no cluster needed)."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tests" / "e2e-playwright" / "scripts" / "ensure-e2e-users.sh"
BASH = shutil.which("bash")
SURVEY_PASSWORD = "Surv3y-secret-#1"
GATE_PASSWORD = "G4te'secret\\x"


def bash_path(path):
    """Translate Windows file paths when subprocess uses Git Bash."""
    if os.name != "nt":
        return str(path)
    cygpath = shutil.which("cygpath")
    if not cygpath:
        raise RuntimeError("Git Bash cygpath is required on Windows")
    return subprocess.check_output([cygpath, "-u", str(path)], text=True).strip()


class EnsureE2EUsersContractTests(unittest.TestCase):
    def test_run_k8s_ensures_accounts_before_the_gate_fixture(self):
        text = (ROOT / "tests/e2e-playwright/scripts/run-k8s.sh").read_text(encoding="utf-8")
        self.assertIn("ensure-e2e-users.sh", text)
        self.assertLess(text.index("ensure-e2e-users.sh"), text.index("fixture-gate-user.mjs"))

    def test_script_never_puts_passwords_in_arguments(self):
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertNotIn("set -x", text)
        self.assertNotRegex(text, r"exec psql[^\n]*E2E_(GATE_)?PASSWORD")

    @unittest.skipUnless(BASH, "Bash is not installed")
    def test_script_syntax_is_valid(self):
        subprocess.run([BASH, "-n", str(SCRIPT)], check=True)


@unittest.skipUnless(BASH, "Bash is not installed")
class EnsureE2EUsersSimulationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="hu07-users-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        shutil.copytree(ROOT / "infra/k8s", self.root / "infra/k8s")
        (self.root / "tests/e2e-playwright/scripts").mkdir(parents=True)
        shutil.copy(SCRIPT, self.root / "tests/e2e-playwright/scripts" / SCRIPT.name)
        self.bin = self.root / "mock-bin"
        self.bin.mkdir()
        self.argv = self.root / "argv.log"
        self.stdin = self.root / "stdin.log"
        fake = self.bin / "kubectl"
        fake.write_text(
            '#!/usr/bin/env bash\n'
            'set -euo pipefail\n'
            'printf "%s\\n" "$*" >> "$MOCK_ARGV_LOG"\n'
            'if [[ " $* " == *" config get-contexts -o name "* ]]; then echo circleguard-dev; exit 0; fi\n'
            'cat >> "$MOCK_STDIN_LOG"\n'
            'printf "%s\\n" "${MOCK_RESULT:-2\n1}"\n',
            encoding="utf-8",
            newline="\n",
        )
        fake.chmod(0o755)
        self.env = {k: v for k, v in os.environ.items() if k not in ("KUBE_CONTEXT", "KUBECONFIG")}
        self.env.update(
            PATH=f"{bash_path(self.bin)}:/usr/bin:/bin",
            MOCK_ARGV_LOG=bash_path(self.argv),
            MOCK_STDIN_LOG=bash_path(self.stdin),
            E2E_USERNAME="e2e_survey",
            E2E_PASSWORD=SURVEY_PASSWORD,
            E2E_GATE_USERNAME="e2e_gate",
            E2E_GATE_PASSWORD=GATE_PASSWORD,
        )

    def run_script(self, env_name="dev", **extra):
        return subprocess.run(
            [BASH, bash_path(self.root / "tests/e2e-playwright/scripts" / SCRIPT.name), env_name],
            cwd=self.root,
            env=dict(self.env, **extra),
            capture_output=True,
            text=True,
        )

    def test_creates_accounts_without_leaking_passwords(self):
        res = self.run_script()
        self.assertEqual(res.returncode, 0, res.stderr)
        argv = self.argv.read_text(encoding="utf-8")
        sql = self.stdin.read_text(encoding="utf-8")
        self.assertIn("--context circleguard-dev -n circleguard-dev exec -i statefulset/postgres", argv)
        for secret in (SURVEY_PASSWORD, GATE_PASSWORD):
            self.assertNotIn(secret, argv)
            self.assertNotIn(secret, res.stdout + res.stderr)
        self.assertIn("\\set sp 'Surv3y-secret-#1'", sql)
        self.assertIn("\\set gp 'G4te\\'secret\\\\x'", sql)  # quote and backslash escaped for psql
        self.assertIn("crypt(:'gp', gen_salt('bf', 10))", sql)
        self.assertIn("'GATE_STAFF'", sql)
        self.assertIn("'STUDENT'", sql)
        self.assertIn("ON CONFLICT (user_id, role_id) DO NOTHING", sql)

    def test_only_touches_the_dedicated_accounts(self):
        sql_text = (ROOT / "tests/e2e-playwright/scripts/ensure-e2e-users.sh").read_text(encoding="utf-8")
        for seeded in ("staff_guard", "health_user", "super_admin"):
            self.assertEqual(self.run_script(E2E_GATE_USERNAME=seeded).returncode, 2)
            self.assertEqual(self.run_script(E2E_USERNAME=seeded).returncode, 2)
            self.assertNotIn(f"'{seeded}'", sql_text.split("emit_sql()")[1])

    def test_rejects_same_account_twice_and_bad_names(self):
        self.assertEqual(self.run_script(E2E_USERNAME="e2e_gate").returncode, 2)
        self.assertEqual(self.run_script(E2E_GATE_USERNAME="x'; DROP TABLE local_users;--").returncode, 2)

    def test_only_runs_for_dev(self):
        self.assertEqual(self.run_script("stage").returncode, 2)
        self.assertEqual(self.run_script("prod").returncode, 2)

    def test_fails_when_verification_does_not_match(self):
        res = self.run_script(MOCK_RESULT="1\n0")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("verification failed", res.stderr)


if __name__ == "__main__":
    unittest.main()
