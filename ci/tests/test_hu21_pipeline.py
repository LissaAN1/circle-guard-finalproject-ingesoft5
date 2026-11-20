"""HU-21: offline checks of the Locust and ZAP stages.

Nothing here contacts Jenkins, Docker or a cluster: docker, kubectl, curl and jq are
replaced by mock executables, and Locust's statistics come from a fixture CSV.
"""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import types
import unittest.mock
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VARS = ROOT / "ci/shared-library/vars"
PERF = ROOT / "tests/performance"
BASH = shutil.which("bash")

sys.path.insert(0, str(PERF))
import evaluate  # noqa: E402

HEADER = ("Type,Name,Request Count,Failure Count,Median Response Time,Average Response Time,"
          "Min Response Time,Max Response Time,Average Content Size,Requests/s,Failures/s,"
          "50%,66%,75%,80%,90%,95%,98%,99%,99.9%,99.99%,100%\n")


def stats_csv(rows):
    """rows: (type, name, count, failures, p95, rps)"""
    body = "".join(f"{t},{n},{c},{f},10,10,1,99,10,{rps},0,10,10,10,10,10,{p95},10,10,10,10,10\n"
                   for t, n, c, f, p95, rps in rows)
    return HEADER + body


def healthy_rows(**override):
    rows = {
        "gate: qr generate": ("GET", "gate: qr generate", 600, 0, 120, 4.0),
        "gate: validate": ("POST", "gate: validate", 600, 0, 60, 4.0),
        "survey: active questionnaire": ("GET", "survey: active questionnaire", 200, 0, 150, 1.3),
        "survey: submit": ("POST", "survey: submit", 200, 0, 300, 1.3),
        "Aggregated": ("", "Aggregated", 1600, 0, 250, 10.6),
    }
    rows.update(override)
    return list(rows.values())


def bash_path(path):
    if os.name != "nt":
        return str(path)
    return subprocess.check_output([shutil.which("cygpath"), "-u", str(path)], text=True).strip()


class PipelineContract(unittest.TestCase):
    def test_performance_and_zap_run_on_stage_before_prod(self):
        code = (VARS / "circleguardPipeline.groovy").read_text(encoding="utf8")
        ordered = ["stage('Deploy Stage')", "stage('E2E Tests')", "stage('Performance STAGE')",
                   "stage('ZAP Baseline STAGE')", "stage('Terraform Plan PROD')", "stage('Approve Prod')"]
        positions = [code.index(s) for s in ordered]
        self.assertEqual(positions, sorted(positions))
        self.assertIn("cgPerformance(environment: 'stage')", code)
        self.assertIn("cgZap(environment: 'stage')", code)

    def test_steps_publish_reports_and_block_on_failure(self):
        perf = (VARS / "cgPerformance.groovy").read_text(encoding="utf8")
        zap = (VARS / "cgZap.groovy").read_text(encoding="utf8")
        for code, report in ((perf, "locust.html"), (zap, "zap-report.html")):
            self.assertIn("publishHTML", code)
            self.assertIn(report, code)
            self.assertIn("archiveArtifacts", code)
            self.assertIn("kubeconfig-${target}", code)
            self.assertIn("promotion blocked", code)
        self.assertIn("circleguard-stage-e2e-survey", perf)

    def test_targets_are_declared_for_both_flows(self):
        targets = json.loads((PERF / "targets.json").read_text(encoding="utf8"))
        names = set(targets["requests"])
        self.assertTrue({"gate: validate", "survey: submit"} <= names)
        self.assertEqual(set(targets["aggregate"]), {"p95_ms", "min_rps", "max_error_rate"})
        locustfile = (PERF / "locustfile.py").read_text(encoding="utf8")
        for name in names:
            self.assertIn(f'name="{name}"', locustfile, f"{name} has a target but no request")

    def test_zap_baseline_is_passive_and_pinned(self):
        src = (ROOT / "ci/scripts/zap-run.sh").read_text(encoding="utf8")
        self.assertIn("zap-baseline.py", src)
        self.assertNotIn("zap-full-scan", src)
        self.assertRegex(src, r"zaproxy/zap-stable:\d+\.\d+\.\d+")
        self.assertRegex((ROOT / "tests/performance/run-k8s.sh").read_text(encoding="utf8"),
                         r"locustio/locust:\d+\.\d+\.\d+")


class TargetEvaluation(unittest.TestCase):
    targets = json.loads((PERF / "targets.json").read_text(encoding="utf8"))

    def run_eval(self, rows):
        with tempfile.TemporaryDirectory() as tmp:
            csv_path = Path(tmp) / "locust_stats.csv"
            csv_path.write_text(stats_csv(rows), encoding="utf8")
            return evaluate.evaluate(evaluate.load_stats(csv_path), self.targets)

    def failed(self, checks):
        return {(c["scope"], c["metric"]) for c in checks if not c["ok"]}

    def test_run_within_targets_passes(self):
        self.assertEqual(self.failed(self.run_eval(healthy_rows())), set())

    def test_slow_gate_validation_fails_its_p95(self):
        rows = healthy_rows(**{"gate: validate": ("POST", "gate: validate", 600, 0, 900, 4.0)})
        self.assertEqual(self.failed(self.run_eval(rows)), {("gate: validate", "p95_ms")})

    def test_error_rate_and_throughput_are_checked(self):
        rows = healthy_rows(Aggregated=("", "Aggregated", 1000, 50, 250, 3.0))
        self.assertEqual(self.failed(self.run_eval(rows)),
                         {("Aggregated", "error_rate"), ("Aggregated", "rps")})

    def test_a_flow_that_never_ran_fails(self):
        rows = [r for r in healthy_rows() if r[1] != "survey: submit"]
        self.assertIn(("survey: submit", "p95_ms"), self.failed(self.run_eval(rows)))

    def test_main_writes_summary_and_exit_code(self):
        with tempfile.TemporaryDirectory() as tmp:
            csv_path = Path(tmp) / "locust_stats.csv"
            csv_path.write_text(stats_csv(healthy_rows(Aggregated=("", "Aggregated", 1600, 0, 2000, 10.6))))
            rc = evaluate.main(["evaluate.py", str(csv_path), str(PERF / "targets.json"), tmp])
            self.assertEqual(rc, 1)
            summary = json.loads((Path(tmp) / "summary.json").read_text(encoding="utf8"))
            self.assertFalse(summary["passed"])
            self.assertIn("NO CUMPLE", (Path(tmp) / "summary.md").read_text(encoding="utf8"))


class LocustScenario(unittest.TestCase):
    """Load the locustfile with a stub locust module (Locust is not a dependency of the repo)."""

    @classmethod
    def setUpClass(cls):
        stub = types.ModuleType("locust")
        stub.HttpUser = object
        stub.between = lambda a, b: None
        stub.task = lambda weight=1: (lambda f: f)
        sys.modules.setdefault("locust", stub)
        spec = importlib.util.spec_from_file_location("cg_locustfile", PERF / "locustfile.py")
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)

    def test_survey_answers_never_report_symptoms(self):
        answers = self.module.negative_answers({"questions": [
            {"id": "a", "type": "YES_NO"},
            {"id": "b", "type": "MULTIPLE_CHOICE", "options": "None, Mild, Severe"},
            {"id": "c", "type": "TEXT"},
        ]})
        self.assertEqual(answers, {"a": "NO", "b": "None", "c": "NONE"})

    def test_jsonb_options_as_list_or_json_text(self):
        answers = self.module.negative_answers({"questions": [
            {"id": "a", "type": "SINGLE_CHOICE", "options": ["None", "Mild"]},
            {"id": "b", "type": "SINGLE_CHOICE", "options": '["None", "Severe"]'},
        ]})
        self.assertEqual(answers, {"a": "None", "b": "None"})

    def test_credentials_are_required(self):
        with unittest.mock.patch.dict(os.environ, {"E2E_USERNAME": "", "E2E_PASSWORD": ""}):
            with self.assertRaises(RuntimeError):
                self.module.credentials()


MOCK_KUBECTL = """#!/usr/bin/env bash
printf 'kubectl %s\\n' "$*" >> "$MOCK_LOG"
if [[ " $* " == *" config get-contexts -o name "* ]]; then echo "${MOCK_CONTEXT:-circleguard-stage}"; exit 0; fi
if [[ " $* " == *" port-forward "* ]]; then exec sleep 30; fi
"""
MOCK_DOCKER = """#!/usr/bin/env bash
printf 'docker %s\\n' "$*" >> "$MOCK_LOG"
case "$1" in
  inspect|create|rm) exit 0;;
  start) exit "${MOCK_ZAP_RC:-0}";;
  cp)
    if [[ "$2" == *:/zap/wrk/. && "${MOCK_NO_REPORT:-0}" != 1 ]]; then
      mkdir -p "$3"; echo '<html>zap</html>' > "$3/zap-report.html"
    fi
    exit 0;;
  run)
    args=("$@")
    for i in "${!args[@]}"; do
      if [[ "${args[$i]}" == --entrypoint ]]; then exec "$MOCK_PYTHON" "${args[@]:$((i+3))}"; fi
      if [[ "${args[$i]}" == --csv ]]; then cp "$MOCK_STATS" "${args[$((i+1))]}_stats.csv"; exit 1; fi
    done
    exit 0;;
esac
"""


@unittest.skipUnless(BASH, "Bash is not installed")
class ScriptSimulation(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix="hu21-")
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        (self.root / "ci/scripts").mkdir(parents=True)
        (self.root / "infra/k8s").mkdir(parents=True)
        shutil.copy2(ROOT / "ci/scripts/zap-run.sh", self.root / "ci/scripts/zap-run.sh")
        shutil.copy2(ROOT / "infra/k8s/lib.sh", self.root / "infra/k8s/lib.sh")
        shutil.copytree(ROOT / "ci/zap", self.root / "ci/zap")
        shutil.copytree(PERF, self.root / "tests/performance",
                        ignore=shutil.ignore_patterns("__pycache__"))
        self.bin = self.root / "mock-bin"
        self.bin.mkdir()
        for name, body in (("docker", MOCK_DOCKER), ("curl", "#!/usr/bin/env bash\nexit 0\n"),
                           ("jq", "#!/usr/bin/env bash\necho '20 2 5m'\n")):
            (self.bin / name).write_text(body, newline="\n")
            (self.bin / name).chmod(0o755)
        kubectl = self.root / "ci/scripts/kubectl"  # the scripts put ci/scripts first on PATH
        kubectl.write_text(MOCK_KUBECTL, newline="\n")
        kubectl.chmod(0o755)
        self.log = self.root / "calls.log"
        self.stats = self.root / "fixture_stats.csv"
        self.stats.write_text(stats_csv(healthy_rows()), newline="\n")
        self.kubeconfig = self.root / "kubeconfig"
        self.kubeconfig.write_text("mock")
        self.env = dict(os.environ, PATH=f"{bash_path(self.bin)}:/usr/bin:/bin",
                        KUBECONFIG=bash_path(self.kubeconfig), MOCK_LOG=bash_path(self.log),
                        MOCK_STATS=bash_path(self.stats), MOCK_PYTHON=bash_path(Path(sys.executable)),
                        E2E_USERNAME="load-user", E2E_PASSWORD="load-pass")

    def run_script(self, script, env_name="stage", **extra):
        return subprocess.run([BASH, bash_path(self.root / script), env_name], cwd=self.root,
                              env=dict(self.env, **extra), capture_output=True, text=True)

    def test_zap_warnings_publish_without_blocking(self):
        for rc in ("0", "2"):
            result = self.run_script("ci/scripts/zap-run.sh", MOCK_ZAP_RC=rc)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((self.root / "ci/reports/zap/zap-report.html").exists())
        log = self.log.read_text()
        self.assertIn("zap-baseline.py -t http://127.0.0.1:8785/ -c rules.tsv", log)
        self.assertIn("--context circleguard-stage -n circleguard-stage port-forward service/web", log)

    def test_zap_fail_rule_or_scanner_error_blocks(self):
        for rc in ("1", "3"):
            self.assertNotEqual(self.run_script("ci/scripts/zap-run.sh", MOCK_ZAP_RC=rc).returncode, 0)

    def test_zap_without_report_blocks(self):
        self.assertNotEqual(self.run_script("ci/scripts/zap-run.sh", MOCK_NO_REPORT="1").returncode, 0)

    def test_scripts_refuse_a_context_of_another_environment(self):
        for script in ("ci/scripts/zap-run.sh", "tests/performance/run-k8s.sh"):
            result = self.run_script(script, MOCK_CONTEXT="circleguard-prod")
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("port-forward", self.log.read_text() if self.log.exists() else "")

    def test_locust_run_within_targets_passes_even_if_locust_exits_one(self):
        result = self.run_script("tests/performance/run-k8s.sh")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("Veredicto: CUMPLE", result.stdout)
        log = self.log.read_text()
        self.assertIn("-u 20 -r 2 -t 5m", log)
        self.assertNotIn("load-pass", log)  # credentials travel as environment, not arguments

    def test_locust_run_missing_a_target_fails(self):
        self.stats.write_text(stats_csv(healthy_rows(Aggregated=("", "Aggregated", 1600, 400, 250, 10.6))),
                              newline="\n")
        result = self.run_script("tests/performance/run-k8s.sh")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("NO CUMPLE", result.stdout)


if __name__ == "__main__":
    unittest.main()
