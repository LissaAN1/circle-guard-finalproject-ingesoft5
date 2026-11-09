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

STAGE_STEPS = ["cgCheckout", "cgDetectChanges", "cgBuild", "cgTest", "cgIntegrationTest", "cgAnalysis", "cgPackage", "cgPublish"]
# HU-08 deploy steps: cgDeploy is called with args so we check for the prefix, not bare ()
DEPLOY_STEPS_BARE = ["cgE2E", "cgApproveProd"]
DEPLOY_STEPS_WITH_ARGS = ["cgDeploy"]


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
        # libraryPath belongs to the retriever (SCMSourceRetriever), not to LibraryConfiguration
        self.assertNotIn("libraryPath", lib)
        path = lib["retriever"]["modernSCM"]["libraryPath"]
        self.assertEqual(path, "ci/shared-library/")
        self.assertTrue((ROOT / path / "vars").is_dir())

    def test_multibranch_job_reads_root_jenkinsfile(self):
        script = self.casc["jobs"][0]["script"]
        self.assertIn("multibranchPipelineJob('circleguard')", script)
        self.assertIn("scriptPath('Jenkinsfile')", script)
        self.assertIn("buildOriginPRMerge(true)", script)
        self.assertNotIn("password", script.lower())

    def test_scan_uses_username_password_credential(self):
        # GitHub Branch Source ignores Secret text credentials (anonymous scan, 60 calls/hour)
        script = self.casc["jobs"][0]["script"]
        self.assertIn("scanCredentialsId('github-scan')", script)
        remote = (JENKINS / "ci-remote.sh").read_text(encoding="utf8")
        self.assertRegex(remote, r'usernamePassword:[^\n]*\\n[^\n]*\\n[^\n]*id: "github-scan"')

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
                         "configuration-as-code", "matrix-auth", "junit", "credentials-binding", "jacoco"):
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

    def test_pipeline_wires_deploy_steps(self):
        pipeline = (VARS / "circleguardPipeline.groovy").read_text(encoding="utf8")
        for step in DEPLOY_STEPS_BARE:
            with self.subTest(step=step):
                self.assertIn(f"{step}()", pipeline)
                self.assertTrue((VARS / f"{step}.groovy").is_file())
        for step in DEPLOY_STEPS_WITH_ARGS:
            with self.subTest(step=step):
                self.assertIn(f"{step}(", pipeline)
                self.assertTrue((VARS / f"{step}.groovy").is_file())

    def test_braces_are_balanced(self):
        for f in VARS.glob("*.groovy"):
            with self.subTest(var=f.name):
                text = re.sub(r"//.*", "", f.read_text(encoding="utf8"))
                self.assertEqual(text.count("{"), text.count("}"))
                self.assertEqual(text.count("("), text.count(")"))

    def test_checkout_exports_git_commit(self):
        text = (VARS / "cgCheckout.groovy").read_text(encoding="utf8")
        self.assertIn("env.GIT_COMMIT", text)

    def test_latest_tag_is_never_used(self):
        for f in list(VARS.glob("*.groovy")) + [ROOT / "Jenkinsfile"] + list((ROOT / "ci" / "scripts").glob("*.sh")):
            text = f.read_text(encoding="utf8")
            with self.subTest(file=f.name):
                self.assertNotRegex(text, r":latest\b")


class QualityGateTests(unittest.TestCase):
    """HU-05: JaCoCo coverage and the blocking SonarQube quality gate."""

    CORE = ["auth", "identity", "promotion", "form", "gateway"]

    def unit_info(self, unit, field):
        return subprocess.run([BASH, str(ROOT / "ci" / "scripts" / "unit-info.sh"), unit, field],
                              check=True, capture_output=True, text=True).stdout.strip()

    def test_core_services_are_gated_and_the_rest_are_not(self):
        for u in self.CORE:
            with self.subTest(unit=u):
                self.assertEqual(self.unit_info(u, "quality"), "gate")
        for u in ("notification", "file", "dashboard", "web"):
            with self.subTest(unit=u):
                self.assertEqual(self.unit_info(u, "quality"), "none")

    def test_jacoco_xml_and_html_reports_for_every_module(self):
        build = (ROOT / "build.gradle.kts").read_text(encoding="utf8")
        self.assertIn('apply(plugin = "jacoco")', build)
        self.assertRegex(build, r"xml\.required\.set\(true\)")
        self.assertRegex(build, r"html\.required\.set\(true\)")
        self.assertIn('finalizedBy("jacocoTestReport")', build)

    def test_analysis_waits_for_the_gate_and_feeds_the_jacoco_report(self):
        text = (VARS / "cgAnalysis.groovy").read_text(encoding="utf8")
        self.assertIn("-Dsonar.qualitygate.wait=true", text)
        self.assertIn("sonar.coverage.jacoco.xmlReportPaths", text)
        self.assertIn("ci/scripts/unit-info.sh ${u} quality", text)

    def test_analysis_stage_runs_when_sonar_is_configured_and_precedes_package(self):
        pipeline = (VARS / "circleguardPipeline.groovy").read_text(encoding="utf8")
        self.assertIn("env.SONAR_HOST_URL", pipeline)
        self.assertNotIn("ENABLE_SONAR", pipeline)
        self.assertLess(pipeline.index("stage('Analysis')"), pipeline.index("stage('Package')"))

    def test_coverage_is_published_after_the_tests(self):
        self.assertIn("cgCoverage()", (VARS / "cgTest.groovy").read_text(encoding="utf8"))
        text = (VARS / "cgCoverage.groovy").read_text(encoding="utf8")
        self.assertIn("jacoco(", text)
        self.assertIn("archiveArtifacts", text)

    def test_sonar_host_and_token_reach_jenkins_without_hardcoding(self):
        casc = (JENKINS / "casc.d" / "10-ci.yaml").read_text(encoding="utf8")
        self.assertIn("${SONAR_HOST_URL:-}", casc)
        remote = (JENKINS / "ci-remote.sh").read_text(encoding="utf8")
        self.assertIn('id: "sonar-token"', remote)
        self.assertIn("SONAR_TOKEN", remote)
        compose = yaml.safe_load((JENKINS / "compose.yaml").read_text(encoding="utf8"))
        self.assertIn("SONAR_HOST_URL", compose["services"]["jenkins"]["environment"])


class ScriptSyntaxTests(unittest.TestCase):
    def test_shell_scripts_parse(self):
        scripts = list((ROOT / "ci" / "scripts").glob("*.sh")) + [
            ROOT / "infra" / "bootstrap-ci.sh", JENKINS / "ci-remote.sh", ROOT / "infra" / "bootstrap-jenkins.sh"]
        for s in scripts:
            with self.subTest(script=s.name):
                subprocess.run([BASH, "-n", str(s)], check=True)


if __name__ == "__main__":
    unittest.main()
