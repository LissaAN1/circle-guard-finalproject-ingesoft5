"""HU-17: the fault-injection scripts must be able to put the HPA back after removing it (HU-12)."""
import json
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "observability" / "scripts" / "hpa-control.sh"

LIVE_HPA = {
    "apiVersion": "autoscaling/v2",
    "kind": "HorizontalPodAutoscaler",
    "metadata": {
        "name": "auth", "namespace": "circleguard-dev", "uid": "1b2c", "resourceVersion": "9981",
        "generation": 3, "creationTimestamp": "2026-11-20T10:00:00Z", "managedFields": [{"manager": "kubectl"}],
        "annotations": {"note": "kept"},
    },
    "spec": {"minReplicas": 2, "maxReplicas": 4},
    "status": {"currentReplicas": 2},
}


@unittest.skipUnless(shutil.which("bash") and shutil.which("python3"), "needs bash and python3")
class HpaBackupTest(unittest.TestCase):
    def run_suspend(self, tmp):
        backup = Path(tmp) / "hpa.yaml"
        # kc is stubbed: no cluster is needed. 'get hpa -o name' answers, '-o json' returns the live object.
        stub = f"""
kc() {{
  case "$*" in
    *"get hpa"*"-o name"*) echo horizontalpodautoscaler.autoscaling/auth ;;
    *"get hpa"*"-o json"*) cat <<'JSON'
{json.dumps(LIVE_HPA)}
JSON
    ;;
    *"delete hpa"*) return 0 ;;
    *) return 1 ;;
  esac
}}
NS=circleguard-dev
source "{SCRIPT.as_posix()}"
suspend_hpa auth "{backup.as_posix()}"
"""
        subprocess.run(["bash", "-c", "set -euo pipefail\n" + stub], check=True, capture_output=True, text=True)
        return json.loads(backup.read_text(encoding="utf-8"))

    def test_backup_can_be_recreated(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            saved = self.run_suspend(tmp)
        for field in ("uid", "resourceVersion", "generation", "creationTimestamp", "managedFields"):
            self.assertNotIn(field, saved["metadata"])
        self.assertNotIn("status", saved)

    def test_backup_keeps_what_defines_the_hpa(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            saved = self.run_suspend(tmp)
        self.assertEqual(saved["spec"], LIVE_HPA["spec"])
        self.assertEqual(saved["metadata"]["name"], "auth")
        self.assertEqual(saved["metadata"]["annotations"], {"note": "kept"})


if __name__ == "__main__":
    unittest.main()
