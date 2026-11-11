from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class Hu07PipelineContract(unittest.TestCase):
    def test_stage_is_blocking_and_follows_deploy_dev(self):
        code = (ROOT / 'ci/shared-library/vars/circleguardPipeline.groovy').read_text()
        self.assertIn("stage('E2E on DEV')", code)
        self.assertIn("env.BRANCH_NAME == 'dev'", code)
        # E2E must run AFTER Deploy Dev so it validates the candidate already on the server.
        self.assertGreater(code.index("stage('E2E on DEV')"), code.index("stage('Deploy Dev')"))
        self.assertIn("cgE2E(environment: 'dev')", code)
        self.assertIn("cgE2E(environment: 'stage')", code)

    def test_runner_fails_on_test_failure_and_reports(self):
        code = (ROOT / 'ci/shared-library/vars/cgE2E.groovy').read_text()
        self.assertIn("bash tests/e2e-playwright/scripts/run-dev.sh", code)
        self.assertIn('returnStatus: true', code)
        self.assertIn('if (rc != 0)', code)
        self.assertIn('publishHTML(', code)
        self.assertIn('junit testResults:', code)
        self.assertNotIn('catchError(', code)


if __name__ == '__main__':
    unittest.main()
