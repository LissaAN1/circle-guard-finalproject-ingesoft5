"""Offline HU-01 Python configuration tests (no Docker, IAM or network)."""
import importlib.util
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


if __name__ == "__main__":
    unittest.main()
