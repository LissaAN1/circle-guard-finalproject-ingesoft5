"""HU-24: the chaos experiments must stay inside dev and be bounded."""
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
CHAOS = ROOT / "infra" / "chaos"


def docs(path):
    return [d for d in yaml.safe_load_all(path.read_text(encoding="utf-8")) if d]


class ChaosTest(unittest.TestCase):
    def test_at_least_two_experiments_with_a_hypothesis(self):
        files = sorted((CHAOS / "experiments").glob("*.yaml"))
        self.assertGreaterEqual(len(files), 2)
        for f in files:
            with self.subTest(file=f.name):
                self.assertIn("Hypothesis", f.read_text(encoding="utf-8"))

    def test_experiments_only_touch_dev(self):
        for f in (CHAOS / "experiments").glob("*.yaml"):
            for d in docs(f):
                with self.subTest(file=f.name):
                    self.assertEqual(d["metadata"]["namespace"], "circleguard-dev")
                    self.assertEqual(d["spec"]["selector"]["namespaces"], ["circleguard-dev"])
                    self.assertTrue(d["spec"]["selector"]["labelSelectors"])

    def test_experiments_that_hold_a_fault_have_a_duration(self):
        for f in (CHAOS / "experiments").glob("*.yaml"):
            for d in docs(f):
                if d["spec"]["action"] != "pod-kill":  # pod-kill is instantaneous
                    with self.subTest(file=f.name):
                        self.assertRegex(d["spec"]["duration"], r"^\d+[sm]$")

    def test_controller_is_filtered_to_annotated_namespaces(self):
        chart = next(d for d in docs(CHAOS / "chaos-mesh.yaml") if d["kind"] == "HelmChart")
        values = yaml.safe_load(chart["spec"]["valuesContent"])
        self.assertTrue(values["controllerManager"]["enableFilterNamespace"])
        self.assertEqual(values["chaosDaemon"]["runtime"], "containerd")


if __name__ == "__main__":
    unittest.main()
