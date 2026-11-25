"""HU-25 tests: no AWS access, the cost data is built by hand."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import cost_report  # noqa: E402
import savings  # noqa: E402


class SavingsTest(unittest.TestCase):
    def test_scheduled_hours_for_the_default_window(self):
        # 13 h a day, 5 days a week, 52/12 weeks a month.
        self.assertAlmostEqual(savings.scheduled_hours(7, 20), 13 * 5 * 52 / 12)

    def test_invalid_window_is_rejected(self):
        for start, stop in ((20, 7), (7, 7), (-1, 10), (7, 25)):
            with self.assertRaises(ValueError):
                savings.scheduled_hours(start, stop)

    def test_saving_is_always_on_minus_scheduled(self):
        res = savings.estimate(0.1, {"dev": 1, "stage": 2}, 7, 20)
        for row in res["rows"]:
            self.assertAlmostEqual(row["saving"], row["always_on"] - row["scheduled"])
            self.assertGreater(row["saving"], 0)
        stage = next(r for r in res["rows"] if r["env"] == "stage")
        self.assertAlmostEqual(stage["always_on"], 2 * 0.1 * 730)

    def test_volumes_are_not_reduced_by_the_schedule(self):
        res = savings.estimate(0.1, {"dev": 1}, 7, 20, volume_gb=30, gb_price=0.08)
        self.assertAlmostEqual(res["rows"][0]["volumes"], 30 * 0.08)

    def test_markdown_has_a_total_row(self):
        res = savings.estimate(0.09576, {"dev": 1, "stage": 2}, 7, 20)
        self.assertIn("| **Total** |", savings.to_markdown(res, 0.09576, 7, 20))


class CostReportTest(unittest.TestCase):
    def test_tag_keys_are_cleaned(self):
        self.assertEqual(cost_report.clean_tag("Environment$dev"), "dev")
        self.assertEqual(cost_report.clean_tag("Environment$"), "sin etiqueta")

    def test_grouped_adds_up_the_periods(self):
        periods = [
            {"Groups": [{"Keys": ["A"], "Metrics": {"UnblendedCost": {"Amount": "1.5"}}}]},
            {"Groups": [{"Keys": ["A"], "Metrics": {"UnblendedCost": {"Amount": "0.5"}}}]},
        ]
        self.assertEqual(cost_report.grouped(periods), {"A": 2.0})

    def test_net_zero_is_not_printed_as_negative(self):
        text = cost_report.build("2026-11-01", "2026-11-21", {"Environment$": 27.45}, {"EC2": 27.45}, -27.45)
        self.assertIn("Neto cobrado: **0.00 USD**", text)
        self.assertNotIn("-0.00", text)

    def test_report_states_gross_credits_and_net(self):
        text = cost_report.build(
            "2026-11-01", "2026-11-21",
            {"Environment$dev": 3.0, "Environment$": 1.0},
            {"EC2": 4.0},
            -4.0,
        )
        self.assertIn("Gasto bruto: **4.00 USD**", text)
        self.assertIn("Neto cobrado: **0.00 USD**", text)
        self.assertIn("| dev | 3.00 |", text)
        self.assertIn("| sin etiqueta | 1.00 |", text)


if __name__ == "__main__":
    unittest.main()
