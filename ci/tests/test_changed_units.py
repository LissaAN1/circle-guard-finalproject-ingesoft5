"""Offline HU-04 tests for ci/scripts (no Docker, Jenkins or network)."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ALL = ["auth", "identity", "promotion", "notification", "form", "file", "gateway", "dashboard", "web"]
BASH = shutil.which("bash")


def sh(*args, cwd, env=None):
    e = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
    e.update(env or {})
    return subprocess.run(args, cwd=cwd, env=e, check=True, capture_output=True, text=True).stdout


class ChangedUnitsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        (Path(self.tmp) / "ci").mkdir()
        shutil.copytree(ROOT / "ci" / "scripts", Path(self.tmp) / "ci" / "scripts")
        shutil.copy(ROOT / "ci" / "units.conf", Path(self.tmp) / "ci" / "units.conf")
        sh("git", "init", "-q", "-b", "main", cwd=self.tmp)
        self.touch("README.md")
        self.commit("chore: init")

    def touch(self, rel, text="x"):
        p = Path(self.tmp) / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text + os.urandom(4).hex())

    def commit(self, msg):
        sh("git", "add", "-A", cwd=self.tmp)
        sh("git", "commit", "-q", "-m", msg, cwd=self.tmp)

    def units(self, base="HEAD~1", env=None):
        out = sh(BASH, "ci/scripts/changed-units.sh", base, cwd=self.tmp, env=env)
        return out.split()

    def test_one_service_change_runs_only_that_service(self):
        self.touch("services/circleguard-form-service/src/A.java")
        self.commit("feat(form): a")
        self.assertEqual(self.units(), ["form"])

    def test_two_services_keep_manifest_order(self):
        self.touch("services/circleguard-gateway-service/src/A.java")
        self.touch("services/circleguard-auth-service/src/B.java")
        self.commit("feat: ab")
        self.assertEqual(self.units(), ["auth", "gateway"])

    def test_mobile_change_runs_web(self):
        self.touch("mobile/app/index.tsx")
        self.commit("feat(mobile): a")
        self.assertEqual(self.units(), ["web"])

    def test_root_build_change_runs_everything(self):
        for root_file in ("build.gradle.kts", "settings.gradle.kts", "gradle/wrapper/gradle-wrapper.properties", "Jenkinsfile", "ci/shared-library/vars/a.groovy"):
            with self.subTest(root_file=root_file):
                self.touch(root_file)
                self.commit(f"chore: {root_file}")
                self.assertEqual(self.units(), ALL)

    def test_docs_and_infra_change_runs_nothing(self):
        self.touch("docs/a.md")
        self.touch("infra/b.sh")
        self.touch(".github/workflows/c.yml")
        self.commit("docs: a")
        self.assertEqual(self.units(), [])

    def test_mixed_service_and_root_runs_everything(self):
        self.touch("services/circleguard-form-service/src/A.java")
        self.touch("build.gradle.kts")
        self.commit("chore: mixed")
        self.assertEqual(self.units(), ALL)

    def test_missing_base_runs_everything(self):
        self.touch("docs/a.md")
        self.commit("docs: a")
        self.assertEqual(self.units(base="does-not-exist"), ALL)
        self.assertEqual(self.units(base=""), ALL)

    def test_force_all(self):
        self.touch("docs/a.md")
        self.commit("docs: a")
        self.assertEqual(self.units(env={"FORCE_ALL": "true"}), ALL)


class UnitInfoTests(unittest.TestCase):
    def info(self, *args):
        return sh(BASH, "ci/scripts/unit-info.sh", *args, cwd=ROOT).strip()

    def test_service_fields(self):
        self.assertEqual(self.info("form", "gradle"), ":services:circleguard-form-service")
        self.assertEqual(self.info("form", "dockerfile"), "services/circleguard-form-service/Dockerfile")
        self.assertEqual(self.info("form", "image"), "circleguard-form-service")
        self.assertEqual(self.info("form", "context"), ".")

    def test_web_fields(self):
        self.assertEqual(self.info("web", "dockerfile"), "mobile/Dockerfile")
        self.assertEqual(self.info("web", "context"), "mobile")
        self.assertEqual(self.info("web", "image"), "circleguard-web")

    def test_every_manifest_unit_has_a_dockerfile_in_repo(self):
        for unit in self.info("list").split():
            with self.subTest(unit=unit):
                dockerfile = ROOT / self.info(unit, "dockerfile")
                self.assertTrue(dockerfile.is_file(), dockerfile)

    def test_latest_tag_is_rejected(self):
        r = subprocess.run([BASH, "ci/scripts/package-image.sh", "form", "latest"], cwd=ROOT, capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("latest", r.stderr)


if __name__ == "__main__":
    unittest.main()
