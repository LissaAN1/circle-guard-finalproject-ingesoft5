"""Offline HU-04 structural checks for the Jenkins configuration and the shared library."""
import re
import shutil
import subprocess
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
JENKINS = ROOT / "infra" / "bootstrap" / "jenkins"
VARS = ROOT / "ci" / "shared-library" / "vars"
BASH = shutil.which("bash")

STAGE_STEPS = ["cgCheckout", "cgDetectChanges", "cgBuild", "cgTest", "cgAnalysis", "cgPackage", "cgPublish"]


class JenkinsConfigTests(unittest.TestCase):
    def setUp(self):
        self.casc = yaml.safe_load((JENKINS / "casc.d" / "10-ci.yaml").read_text(encoding="utf8"))
        self.compose = yaml.safe_load((JENKINS / "compose.yaml").read_text(encoding="utf8"))

    def test_build_agent_node_is_inbound_websocket(self):
        node = self.casc["jenkins"]["nodes"][0]["permanent"]
        self.assertEqual(node["name"], "build-agent")
        self.assertIn("docker", node["labelString"].split())
        self.assertTrue(node["launcher"]["inbound"]["webSocket"])

    def test_controller_keeps_zero_executors(self):
        base = yaml.safe_load((JENKINS / "casc.yaml").read_text(encoding="utf8"))
        self.assertEqual(base["jenkins"]["numExecutors"], 0)
        self.assertNotIn("nodes", base["jenkins"])

    def test_shared_library_points_to_repo_path(self):
        lib = self.casc["unclassified"]["globalLibraries"]["libraries"][0]
        self.assertEqual(lib["name"], "circleguard-ci")
        self.assertEqual(lib["libraryPath"], "ci/shared-library/")
        self.assertTrue((ROOT / lib["libraryPath"] / "vars").is_dir())

    def test_multibranch_job_reads_root_jenkinsfile(self):
        script = self.casc["jobs"][0]["script"]
        self.assertIn("multibranchPipelineJob('circleguard')", script)
        self.assertIn("scriptPath('Jenkinsfile')", script)
        self.assertIn("buildOriginPRMerge(true)", script)
        self.assertNotIn("password", script.lower())

    def test_no_secret_values_in_casc(self):
        text = (JENKINS / "casc.d" / "10-ci.yaml").read_text(encoding="utf8")
        self.assertNotRegex(text, r"ghp_[A-Za-z0-9]+")
        self.assertNotIn("password:", text)

    def test_compose_profiles_and_docker_socket(self):
        services = self.compose["services"]
        self.assertNotIn("profiles", services["jenkins"])
        self.assertEqual(services["build-agent"]["profiles"], ["ci"])
        self.assertEqual(services["webhook-relay"]["profiles"], ["webhook"])
        self.assertNotIn("/var/run/docker.sock", " ".join(services["jenkins"].get("volumes", [])))
        self.assertIn("/var/run/docker.sock:/var/run/docker.sock", services["build-agent"]["volumes"])

    def test_plugins_are_pinned(self):
        dockerfile = (JENKINS / "Dockerfile").read_text(encoding="utf8")
        plugins = re.findall(r"^\s+([a-z0-9-]+):(\S+?)(?:\s*\\)?$", dockerfile, re.M)
        names = {n for n, _ in plugins}
        for required in ("workflow-aggregator", "github-branch-source", "job-dsl", "pipeline-groovy-lib",
                         "configuration-as-code", "matrix-auth", "junit", "credentials-binding"):
            self.assertIn(required, names)
        self.assertTrue(all(v and v != "latest" for _, v in plugins))


class SharedLibraryTests(unittest.TestCase):
    def test_jenkinsfile_uses_the_library(self):
        text = (ROOT / "Jenkinsfile").read_text(encoding="utf8")
        self.assertIn("@Library('circleguard-ci') _", text)
        self.assertIn("circleguardPipeline()", text)

    def test_every_var_defines_call(self):
        for f in VARS.glob("*.groovy"):
            with self.subTest(var=f.name):
                self.assertIn("def call(", f.read_text(encoding="utf8"))

    def test_pipeline_wires_every_stage_step(self):
        pipeline = (VARS / "circleguardPipeline.groovy").read_text(encoding="utf8")
        for step in STAGE_STEPS:
            with self.subTest(step=step):
                self.assertIn(f"{step}()", pipeline)
                self.assertTrue((VARS / f"{step}.groovy").is_file())

    def test_braces_are_balanced(self):
        for f in VARS.glob("*.groovy"):
            with self.subTest(var=f.name):
                text = re.sub(r"//.*", "", f.read_text(encoding="utf8"))
                self.assertEqual(text.count("{"), text.count("}"))
                self.assertEqual(text.count("("), text.count(")"))

    def test_latest_tag_is_never_used(self):
        for f in list(VARS.glob("*.groovy")) + [ROOT / "Jenkinsfile"] + list((ROOT / "ci" / "scripts").glob("*.sh")):
            text = f.read_text(encoding="utf8")
            with self.subTest(file=f.name):
                self.assertNotRegex(text, r":latest\b")


class ScriptSyntaxTests(unittest.TestCase):
    def test_shell_scripts_parse(self):
        scripts = list((ROOT / "ci" / "scripts").glob("*.sh")) + [
            ROOT / "infra" / "bootstrap-ci.sh", JENKINS / "ci-remote.sh", ROOT / "infra" / "bootstrap-jenkins.sh"]
        for s in scripts:
            with self.subTest(script=s.name):
                subprocess.run([BASH, "-n", str(s)], check=True)


if __name__ == "__main__":
    unittest.main()
