"""HU-23: the mesh definition must be strict where it claims to be and stay out of stage and prod."""
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
MESH = ROOT / "infra" / "mesh"


def docs(path):
    return [d for d in yaml.safe_load_all(path.read_text(encoding="utf-8")) if d]


class MeshTest(unittest.TestCase):
    def test_private_keys_are_ignored_by_git(self):
        self.assertIn("infra/mesh/.private/", (ROOT / ".gitignore").read_text(encoding="utf-8"))

    def test_issuer_key_is_not_in_any_manifest(self):
        for f in MESH.rglob("*.yaml"):
            self.assertNotIn("PRIVATE KEY", f.read_text(encoding="utf-8"), f.name)

    def test_demo_namespace_rejects_unauthenticated_traffic(self):
        ns = next(d for d in docs(MESH / "demo" / "mesh-demo.yaml") if d["kind"] == "Namespace")
        self.assertEqual(ns["metadata"]["annotations"]["config.linkerd.io/default-inbound-policy"], "all-authenticated")
        self.assertEqual(ns["metadata"]["annotations"]["linkerd.io/inject"], "enabled")

    def test_canary_splits_between_two_versions(self):
        route = next(d for d in docs(MESH / "demo" / "mesh-demo.yaml") if d["kind"] == "HTTPRoute")
        refs = route["spec"]["rules"][0]["backendRefs"]
        self.assertEqual({r["name"] for r in refs}, {"hello-v1", "hello-v2"})
        self.assertEqual(sum(r["weight"] for r in refs), 100)

    def test_control_plane_uses_a_secret_issuer_and_small_requests(self):
        chart = next(d for d in docs(MESH / "linkerd.yaml") if d["kind"] == "HelmChart" and d["metadata"]["name"] == "linkerd-control-plane")
        text = chart["spec"]["valuesContent"].replace("__TRUST_ANCHOR__", "x")
        values = yaml.safe_load(text)
        self.assertEqual(values["identity"]["issuer"]["scheme"], "kubernetes.io/tls")
        self.assertEqual(values["controllerReplicas"], 1)

    def test_injection_is_declared_for_dev_only(self):
        for env, expected in (("dev", True), ("stage", False), ("prod", False)):
            text = (ROOT / "infra" / "k8s" / "overlays" / env / "kustomization.yaml").read_text(encoding="utf-8")
            self.assertEqual("linkerd.io/inject" in text, expected, env)


if __name__ == "__main__":
    unittest.main()
