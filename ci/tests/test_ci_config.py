"""Offline HU-04 structural checks for the Jenkins configuration and the shared library."""
import os
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

    # Bloque A: release completo y publicacion obligatoria.

    def test_main_release_forces_all_units(self):
        text = (VARS / "cgDetectChanges.groovy").read_text(encoding="utf8")

        self.assertRegex(
            text,
            r"boolean\s+fullRelease\s*=\s*"
            r"env\.BRANCH_NAME\s*==\s*'main'\s*&&\s*!env\.CHANGE_ID"
        )
        self.assertRegex(
            text,
            r"String\s+forceAll\s*=\s*fullRelease\s*\?\s*"
            r"'true'\s*:\s*\(env\.FORCE_ALL\s*\?:\s*'false'\)"
        )
        self.assertIn('"FORCE_ALL=${forceAll}"', text)
        self.assertIn("Release main: processing all units", text)

    def test_dev_preserves_incremental_detection(self):
        text = (VARS / "cgDetectChanges.groovy").read_text(encoding="utf8")

        self.assertIn("env.BRANCH_NAME == 'main' && !env.CHANGE_ID", text)
        self.assertIn("(env.FORCE_ALL ?: 'false')", text)
        self.assertIn("env.BRANCH_NAME in ['dev', 'main']", text)
        self.assertIn("base = 'HEAD~1'", text)
        self.assertIn('ci/scripts/changed-units.sh "$CG_BASE"', text)

    def test_publish_fails_when_nexus_credential_is_missing(self):
        text = (VARS / "cgPublish.groovy").read_text(encoding="utf8")

        self.assertIn("credentialsId: 'nexus-publisher'", text)
        self.assertIn("catch (hudson.AbortException e)", text)
        self.assertIn("e.message?.contains('nexus-publisher')", text)
        self.assertIn("Publish aborted: required Nexus credential", text)
        self.assertIn("nexus-publisher is unavailable", text)
        self.assertNotIn("Publish skipped:", text)

        self.assertRegex(
            text,
            r"if\s*\(e\.message\?\.contains\('nexus-publisher'\)\)"
            r"\s*\{\s*error\s*\("
        )

        self.assertRegex(
            text,
            r"\}\s*throw e\s*\}"
        )

    def test_force_all_returns_nine_units(self):
        script = ROOT / "ci" / "scripts" / "changed-units.sh"

        environment = os.environ.copy()
        environment["FORCE_ALL"] = "true"

        result = subprocess.run(
            [BASH, str(script), "HEAD~1"],
            cwd=ROOT,
            env=environment,
            capture_output=True,
            text=True,
            check=True
        )

        units = result.stdout.splitlines()

        expected = {
            "auth",
            "identity",
            "promotion",
            "notification",
            "form",
            "file",
            "gateway",
            "dashboard",
            "web",
        }

        self.assertEqual(len(units), 9)
        self.assertEqual(set(units), expected)


class ProductionReleaseGuardTests(unittest.TestCase):
    """Block D: structural safety checks; Jenkins authorization is tested separately."""

    def setUp(self):
        self.pipeline = (VARS / "circleguardPipeline.groovy").read_text(encoding="utf8")
        self.approval = (VARS / "cgApproveProd.groovy").read_text(encoding="utf8")

    def prod_stage(self, name):
        start = self.pipeline.index(f"stage('{name}')")
        next_stage = self.pipeline.find("stage('", start + len(f"stage('{name}')"))
        return self.pipeline[start:next_stage if next_stage != -1 else len(self.pipeline)]

    def test_production_stages_require_explicit_enablement(self):
        guard = "expression { env.CG_ENABLE_PROD_RELEASE == 'true' }"
        for name in ("Approve Prod", "Deploy Prod"):
            with self.subTest(stage=name):
                stage = self.prod_stage(name)
                self.assertIn(guard, stage)
                self.assertLess(stage.index(guard), stage.index("steps {"))
                self.assertIn("expression { env.BRANCH_NAME == 'main' }", stage)
                self.assertIn("expression { !env.CHANGE_ID }", stage)
                self.assertIn("expression { env.NEXUS_REGISTRY?.trim() as Boolean }", stage)

    def test_deploy_prod_requires_image_tag(self):
        stage = self.prod_stage("Deploy Prod")
        self.assertIn("expression { env.CG_IMAGE_TAG?.trim() as Boolean }", stage)
        self.assertIn("cgDeploy(environment: 'prod', appVersion: env.CG_IMAGE_TAG)", stage)

    def test_approval_rejects_missing_approvers_and_disabled_release(self):
        self.assertIn("String approvers = env.CG_PROD_APPROVERS?.trim()", self.approval)
        self.assertRegex(self.approval, r"if\s*\(!approvers\)\s*\{\s*error\('cgApproveProd: CG_PROD_APPROVERS is required'\)")
        self.assertRegex(self.approval, r"if\s*\(env\.CG_ENABLE_PROD_RELEASE != 'true'\)\s*\{\s*error\('cgApproveProd: production release is disabled'\)")

    def test_approval_rejects_missing_image_tag(self):
        self.assertRegex(self.approval, r"if\s*\(!env\.CG_IMAGE_TAG\?\.trim\(\)\)\s*\{\s*error\('cgApproveProd: release image tag is required'\)")

    def test_approval_restricts_submitter_and_times_out(self):
        self.assertRegex(self.approval, r"submitter\s*:\s*approvers")
        self.assertRegex(self.approval, r"submitterParameter\s*:\s*'CG_PROD_APPROVED_BY'")
        self.assertRegex(self.approval, r"timeout\(time:\s*30,\s*unit:\s*'MINUTES'\)")
        self.assertLess(self.approval.index("timeout("), self.approval.index("input("))

    def test_approval_precedes_deploy_prod(self):
        self.assertLess(self.pipeline.index("stage('Approve Prod')"), self.pipeline.index("stage('Deploy Prod')"))
        self.assertIn("cgApproveProd()", self.prod_stage("Approve Prod"))


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
