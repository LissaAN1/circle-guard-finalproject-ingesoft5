"""Offline HU-01 Python configuration tests (no Docker, IAM or network)."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

BASE = Path(__file__).resolve().parents[1]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


nexus = module("nexus_bootstrap", BASE / "nexus" / "configure.py")
sonar = module("sonar_bootstrap", BASE / "sonarqube" / "configure.py")


class NexusBootstrapTests(unittest.TestCase):
    def test_existing_docker_repo_is_preserved(self):
        existing = {"docker": {"httpPort": 8082}, "storage": {"writePolicy": "ALLOW_ONCE"}}
        with patch.object(nexus, "api", return_value=(200, existing)) as api, patch.object(nexus, "checked") as checked:
            nexus.ensure_repository("secret")
            api.assert_called_once()
            checked.assert_not_called()

    def test_missing_docker_repo_is_created(self):
        existing = {"docker": {"httpPort": 8082}, "storage": {"writePolicy": "ALLOW_ONCE"}}
        with patch.object(nexus, "api", return_value=(404, None)), patch.object(nexus, "checked", side_effect=[None, existing]) as checked:
            nexus.ensure_repository("secret")
            self.assertEqual(checked.call_count, 2)
            self.assertEqual(checked.call_args_list[0].args[2], "POST")

    def test_wrong_connector_fails_closed(self):
        with patch.object(nexus, "api", return_value=(200, {"docker": {"httpPort": 5000}, "storage": {"writePolicy": "ALLOW_ONCE"}})):
            with self.assertRaisesRegex(RuntimeError, "8082"):
                nexus.ensure_repository("secret")

    def test_existing_role_with_privileges_is_preserved(self):
        with patch.object(nexus, "api", return_value=(200, {"privileges": ["a", "b"]})), patch.object(nexus, "checked") as checked:
            nexus.ensure_role("secret", "myrole", ["a"])
            checked.assert_not_called()

    def test_existing_user_with_role_is_preserved(self):
        with patch.object(nexus, "checked", return_value=[{"userId": "cg-reader", "roles": ["circleguard-reader"]}]) as checked:
            nexus.ensure_user("secret", "cg-reader", "secret", "circleguard-reader", "Reader")
            checked.assert_called_once()

    def test_existing_user_without_role_fails_closed(self):
        with patch.object(nexus, "checked", return_value=[{"userId": "cg-reader", "roles": []}]):
            with self.assertRaisesRegex(RuntimeError, "lacks"):
                nexus.ensure_user("secret", "cg-reader", "secret", "circleguard-reader", "Reader")


class SonarBootstrapTests(unittest.TestCase):
    def test_admin_auth_accepts_valid(self):
        with patch.object(sonar, "call", return_value=(200, '{"valid":true}')):
            self.assertTrue(sonar.auth_valid("secret"))

    def test_admin_auth_rejects_invalid(self):
        with patch.object(sonar, "call", return_value=(200, '{"valid":false}')):
            self.assertFalse(sonar.auth_valid("secret"))

    def gate_api(self, gates, conditions, calls):
        """Fake SonarQube API: records POSTs and answers list/show."""
        def fake(path, password, data=None):
            if path.startswith("/api/qualitygates/list"):
                return 200, '{"qualitygates":%s}' % json.dumps([{"name": g} for g in gates])
            if path.startswith("/api/qualitygates/show"):
                return 200, '{"conditions":%s}' % json.dumps(conditions)
            calls.append((path, data))
            return 200, "{}"
        return fake

    def test_quality_gate_is_created_with_coverage_condition(self):
        calls = []
        with patch.object(sonar, "api", self.gate_api([], [], calls)):
            sonar.ensure_quality_gate("secret")
        paths = [c[0] for c in calls]
        self.assertIn("/api/qualitygates/create", paths)
        cond = dict(calls)["/api/qualitygates/create_condition"]
        self.assertEqual((cond["metric"], cond["op"], cond["error"]), ("coverage", "LT", "60"))
        self.assertIn("/api/qualitygates/set_as_default", paths)

    def test_quality_gate_rerun_changes_nothing_but_default(self):
        calls = []
        ok = [{"id": "1", "metric": "coverage", "op": "LT", "error": "60"}]
        with patch.object(sonar, "api", self.gate_api(["CircleGuard"], ok, calls)):
            sonar.ensure_quality_gate("secret")
        self.assertEqual([c[0] for c in calls], ["/api/qualitygates/set_as_default"])

    def test_lenient_threshold_is_replaced(self):
        calls = []
        stale = [{"id": "7", "metric": "coverage", "op": "LT", "error": "10"}]
        with patch.object(sonar, "api", self.gate_api(["CircleGuard"], stale, calls)):
            sonar.ensure_quality_gate("secret")
        paths = [c[0] for c in calls]
        self.assertIn("/api/qualitygates/delete_condition", paths)
        self.assertIn("/api/qualitygates/create_condition", paths)

    def test_stored_token_is_reused_without_generating_a_new_one(self):
        with tempfile.TemporaryDirectory() as tmp:
            secrets = Path(tmp) / "sonar.secrets.env"
            secrets.write_text("SONAR_ADMIN_PASSWORD=x\nSONAR_ANALYSIS_TOKEN=squ_stored\n", encoding="utf-8")
            with patch.object(sonar, "SECRETS", secrets),                  patch.object(sonar, "api", return_value=(200, '{"userTokens":[{"name":"jenkins-ci"}]}')) as api:
                self.assertEqual(sonar.analysis_token("secret"), "squ_stored")
                api.assert_called_once()

    def test_missing_token_is_generated_and_stored(self):
        with tempfile.TemporaryDirectory() as tmp:
            secrets = Path(tmp) / "sonar.secrets.env"
            secrets.write_text("SONAR_ADMIN_PASSWORD=x\n", encoding="utf-8")
            answers = iter([(200, '{"userTokens":[]}'), (200, '{"token":"squ_new"}')])
            with patch.object(sonar, "SECRETS", secrets), patch.object(sonar, "api", lambda *a, **k: next(answers)):
                self.assertEqual(sonar.analysis_token("secret"), "squ_new")
            self.assertIn("SONAR_ANALYSIS_TOKEN=squ_new", secrets.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
