"""HU-18: dashboards versionados, datasources con uid fijo y sin contrasenas en texto plano."""
import importlib.util
import json
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
GRAFANA = ROOT / "observability" / "grafana"
SERVICES = ("auth", "identity", "promotion", "form", "gateway", "dashboard", "file", "notification")


def load_generator():
    spec = importlib.util.spec_from_file_location("generate_dashboards", GRAFANA / "generate_dashboards.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read(name):
    return json.loads((GRAFANA / "dashboards" / name).read_text(encoding="utf-8"))


class GrafanaDashboardsTest(unittest.TestCase):
    def test_json_files_match_the_generator(self):
        expected = load_generator().build_all()
        found = sorted(p.name for p in (GRAFANA / "dashboards").glob("*.json"))
        self.assertEqual(found, sorted(expected))
        for name, content in expected.items():
            with self.subTest(dashboard=name):
                self.assertEqual(read(name), content, "Ejecute generate_dashboards.py y haga commit")

    def test_each_service_dashboard_has_latency_errors_jvm_and_logs(self):
        for service in SERVICES:
            with self.subTest(service=service):
                panels = read(f"circleguard-{service}.json")["panels"]
                exprs = " ".join(t["expr"] for p in panels for t in p["targets"])
                self.assertIn("http_server_requests_seconds_bucket", exprs)
                self.assertIn("SERVER_ERROR", exprs)
                self.assertIn("jvm_memory_used_bytes", exprs)
                self.assertIn(f'service="{service}"', exprs)

    def test_business_dashboard_uses_the_hu17_metrics(self):
        panels = read("circleguard-business.json")["panels"]
        exprs = " ".join(t["expr"] for p in panels for t in p["targets"])
        for metric in ("circleguard_promotions_total", "circleguard_checkins_total",
                       "circleguard_containment_duration_seconds_bucket"):
            self.assertIn(metric, exprs)

    def test_datasources_have_fixed_uids(self):
        path = GRAFANA / "provisioning" / "datasources" / "datasources.yaml"
        config = yaml.safe_load(path.read_text(encoding="utf-8"))
        uids = {d["name"]: d["uid"] for d in config["datasources"]}
        self.assertEqual(uids, {"Prometheus": "prometheus", "Loki": "loki"})

    def test_no_plaintext_grafana_password(self):
        for folder in (ROOT / "observability", ROOT / "infra" / "k8s" / "observability"):
            for path in list(folder.rglob("*.yaml")) + list(folder.rglob("*.yml")):
                with self.subTest(file=str(path.relative_to(ROOT))):
                    self.assertNotIn("ADMIN_PASSWORD=admin", path.read_text(encoding="utf-8"))
        grafana = (ROOT / "infra" / "k8s" / "observability" / "grafana.yaml").read_text(encoding="utf-8")
        self.assertIn("secretKeyRef", grafana)


if __name__ == "__main__":
    unittest.main()