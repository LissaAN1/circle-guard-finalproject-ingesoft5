"""Offline safety tests for CircleGuard's EC2 deployment script.

Runs a temporary copy of the script against fake Docker and flock executables.
Never touches /opt/circleguard, EC2, Jenkins, or a real Docker daemon.
"""
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "ci" / "deploy" / "deploy-remote.sh"
BASH = shutil.which("bash")

SERVICES = {"auth", "identity", "promotion", "form", "gateway", "web"}


def bash_path(path):
    """Translate Windows paths to Git Bash paths; no-op on Linux/macOS."""
    path = str(path)
    if os.name != "nt":
        return path
    cygpath = shutil.which("cygpath")
    if not cygpath:
        raise RuntimeError("Git Bash cygpath is required for these tests on Windows")
    return subprocess.check_output([cygpath, "-u", path], text=True).strip()


class DeployRemoteTests(unittest.TestCase):
    def setUp(self):
        if not BASH:
            self.skipTest("Bash is not available")
        self.temp = tempfile.TemporaryDirectory(prefix="cg-deploy-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env_dir = self.root / "environments"
        self.env_dir.mkdir()
        self.env_file = self.env_dir / ".env"
        self.initial_env = "APP_VERSION=previous-123\nDB_PASSWORD=keep-this-secret\nJWT_SECRET=keep-this-token\n"
        self.env_file.write_text(self.initial_env, encoding="utf8")
        (self.env_dir / "init-db.sql").write_text("-- preserve this file\n", encoding="utf8")
        (self.env_dir / "compose.base.yaml").write_text("services: {}\n", encoding="utf8")
        (self.env_dir / "compose.stage.yaml").write_text("services: {}\n", encoding="utf8")
        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir()
        self.log = self.root / "docker.log"
        self.script = self.root / "deploy-remote.sh"

        original = SCRIPT.read_text(encoding="utf8")
        self.assertEqual(original.count("remote=/opt/circleguard/environments"), 1)
        # Only the local test copy gets a different path. Production source is untouched.
        original = original.replace(
            "remote=/opt/circleguard/environments",
            'remote="' + bash_path(self.env_dir) + '"',
        )
        self.script.write_text(original, encoding="utf8")

        docker_mock = self.bin_dir / "docker"
        docker_mock.write_text(r'''#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "compose" ]] || exit 90
shift
version=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[i]}" == "--env-file" ]]; then
    version="$(sed -n 's/^APP_VERSION=//p' "${args[i+1]}")"
  fi
done
operation=""
for arg in "$@"; do
  case "$arg" in config|pull|up|ps) operation="$arg"; break;; esac
done
printf '%s:%s\n' "$operation" "$version" >> "$MOCK_LOG"
case "$operation" in
  config)
    [[ "$MOCK_FAIL" != "config" ]] || exit 41
    ;;
  pull)
    [[ "$MOCK_FAIL" != "pull" ]] || exit 42
    for service in auth identity promotion form gateway web; do
      [[ " $* " == *" $service "* ]] || exit 43
    done
    for infrastructure in postgres neo4j zookeeper kafka redis openldap; do
      [[ " $* " != *" $infrastructure "* ]] || exit 44
    done
    [[ " $* " != *" --no-deps "* ]] || exit 45
    ;;
  up)
    [[ " $* " == *" --no-build "* ]] || exit 46
    [[ " $* " == *" --wait "* ]] || exit 47
    [[ " $* " == *" --wait-timeout 600 "* ]] || exit 48
    if [[ "$MOCK_FAIL" == "unhealthy" && "$version" == "candidate-456" ]]; then exit 49; fi
    if [[ "$MOCK_FAIL" == "rollback" ]]; then exit 50; fi
    ;;
  ps) ;;
  *) exit 51;;
esac
''', encoding="utf8")
        # File execute bits on Windows/Git Bash may be ignored; chmod on POSIX.
        docker_mock.chmod(0o755)
        flock_mock = self.bin_dir / "flock"
        flock_mock.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf8")
        flock_mock.chmod(0o755)

    def execute(self, failure="none", version="candidate-456"):
        # Keep Git Bash's native PATH intact, adding fake executables inside Bash.
        return subprocess.run(
            [
                BASH, "-c",
                'export PATH="$1:$PATH" MOCK_LOG="$2" MOCK_FAIL="$3"; '
                'exec bash "$4" stage "$5"',
                "cg-deploy-test",
                bash_path(self.bin_dir), bash_path(self.log), failure,
                bash_path(self.script), version,
            ],
            cwd=self.root,
            text=True,
            capture_output=True,
        )

    def operations(self):
        return self.log.read_text(encoding="utf8").splitlines() if self.log.exists() else []

    def assert_private_files_unchanged(self):
        self.assertIn("DB_PASSWORD=keep-this-secret", self.env_file.read_text(encoding="utf8"))
        self.assertIn("JWT_SECRET=keep-this-token", self.env_file.read_text(encoding="utf8"))
        self.assertEqual((self.env_dir / "init-db.sql").read_text(encoding="utf8"), "-- preserve this file\n")

    def test_missing_nexus_image_aborts_before_changing_env(self):
        result = self.execute("pull")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.env_file.read_text(encoding="utf8"), self.initial_env)
        self.assertEqual(self.operations(), ["config:candidate-456", "pull:candidate-456"])

    def test_invalid_compose_aborts_without_deploying(self):
        result = self.execute("config")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.env_file.read_text(encoding="utf8"), self.initial_env)
        self.assertEqual(self.operations(), ["config:candidate-456"])

    def test_success_waits_for_health_and_applies_candidate(self):
        result = self.execute()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.operations(), [
            "config:candidate-456", "pull:candidate-456", "up:candidate-456", "ps:candidate-456"
        ])
        self.assertIn("APP_VERSION=candidate-456", self.env_file.read_text(encoding="utf8"))
        self.assertEqual(list(self.env_dir.glob(".env.backup.*")), [])
        self.assert_private_files_unchanged()

    def test_unhealthy_candidate_attempts_rollback(self):
        result = self.execute("unhealthy")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.env_file.read_text(encoding="utf8"), self.initial_env)
        self.assertEqual(self.operations(), [
            "config:candidate-456",
            "pull:candidate-456",
            "up:candidate-456",
            "up:previous-123",
        ])
        self.assertIn("Rollback completed", result.stderr)
        self.assert_private_files_unchanged()

    def test_failed_rollback_reports_critical_error(self):
        result = self.execute("rollback")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.env_file.read_text(encoding="utf8"), self.initial_env)
        self.assertIn("CRITICAL: rollback failed", result.stderr)
        self.assertEqual(self.operations(), [
            "config:candidate-456", "pull:candidate-456", "up:candidate-456",
            "up:previous-123", "ps:previous-123"
        ])
        self.assert_private_files_unchanged()

    def test_private_files_are_preserved_on_success_and_failure(self):
        self.assertEqual(self.execute().returncode, 0)
        self.assert_private_files_unchanged()
        self.env_file.write_text(self.initial_env, encoding="utf8")
        self.log.unlink()
        self.assertNotEqual(self.execute("pull").returncode, 0)
        self.assert_private_files_unchanged()

    def test_invalid_version_is_rejected_before_docker(self):
        result = self.execute(version="invalid;command")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.env_file.read_text(encoding="utf8"), self.initial_env)
        self.assertEqual(self.operations(), [])


if __name__ == "__main__":
    unittest.main()
