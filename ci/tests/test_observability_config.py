"""HU-17 and HU-19: tracing and metrics settings must sit where Spring Boot reads them."""
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
TRACED = ("form", "promotion", "notification")
ALL = ("auth", "dashboard", "file", "form", "gateway", "identity", "notification", "promotion")


def load(service):
    path = ROOT / "services" / f"circleguard-{service}-service" / "src" / "main" / "resources" / "application.yml"
    return yaml.safe_load(path.read_text(encoding="utf-8"))


class ObservabilityConfigTest(unittest.TestCase):
    def test_traced_services_export_to_jaeger(self):
        for service in TRACED:
            with self.subTest(service=service):
                management = load(service)["management"]
                self.assertIn("probability", management["tracing"]["sampling"])
                self.assertIn("endpoint", management["otlp"]["tracing"])
                # Nested under endpoint they are silently ignored and nothing reaches Jaeger.
                self.assertNotIn("tracing", management.get("endpoint", {}))
                self.assertNotIn("otlp", management.get("endpoint", {}))

    def test_trace_ids_are_in_the_logs(self):
        for service in TRACED:
            with self.subTest(service=service):
                config = load(service)
                self.assertIn("traceId", config["logging"]["pattern"]["level"])
                self.assertNotIn("logging", config["management"])

    def test_prometheus_endpoint_is_exposed_everywhere(self):
        for service in ALL:
            with self.subTest(service=service):
                include = load(service)["management"]["endpoints"]["web"]["exposure"]["include"]
                self.assertIn("prometheus", include)


if __name__ == "__main__":
    unittest.main()
