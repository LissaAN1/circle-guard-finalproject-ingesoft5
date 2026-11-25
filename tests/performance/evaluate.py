#!/usr/bin/env python3
"""HU-21: compare a Locust run with the targets declared in targets.json.

Usage: python evaluate.py <prefix>_stats.csv targets.json <out-dir>
Writes <out-dir>/summary.md and <out-dir>/summary.json and exits 1 when a target is missed,
so the pipeline stage fails instead of only archiving the numbers.
"""
import csv
import json
import sys
from pathlib import Path


def load_stats(path):
    rows = {}
    with open(path, newline="", encoding="utf8") as f:
        for row in csv.DictReader(f):
            rows[row["Name"]] = {
                "requests": int(row["Request Count"]),
                "failures": int(row["Failure Count"]),
                "p95_ms": float(row["95%"]) if row["95%"] not in ("", "N/A") else None,
                "rps": float(row["Requests/s"]),
            }
    if "Aggregated" not in rows:
        raise ValueError(f"{path}: no Aggregated row; is this a Locust *_stats.csv?")
    return rows


def evaluate(stats, targets):
    checks = []

    def add(scope, metric, target, actual, ok):
        checks.append({"scope": scope, "metric": metric, "target": target, "actual": actual, "ok": ok})

    for name, goal in targets["requests"].items():
        row = stats.get(name)
        if row is None or row["requests"] == 0:
            add(name, "p95_ms", goal["p95_ms"], None, False)
            continue
        add(name, "p95_ms", goal["p95_ms"], row["p95_ms"], row["p95_ms"] is not None and row["p95_ms"] <= goal["p95_ms"])
    agg, goal = stats["Aggregated"], targets["aggregate"]
    error_rate = agg["failures"] / agg["requests"] if agg["requests"] else 1.0
    add("Aggregated", "p95_ms", goal["p95_ms"], agg["p95_ms"], agg["p95_ms"] is not None and agg["p95_ms"] <= goal["p95_ms"])
    add("Aggregated", "rps", goal["min_rps"], round(agg["rps"], 2), agg["rps"] >= goal["min_rps"])
    add("Aggregated", "error_rate", goal["max_error_rate"], round(error_rate, 4), error_rate <= goal["max_error_rate"])
    return checks


def to_markdown(checks, stats, targets):
    symbol = {"p95_ms": "≤", "rps": "≥", "error_rate": "≤"}
    load = targets.get("load", {})
    lines = [
        "# HU-21: resultado de Locust contra los objetivos",
        "",
        f"Carga: {load.get('users')} usuarios, {load.get('spawn_rate')} por segundo, {load.get('duration')}.",
        "",
        "| Alcance | Métrica | Objetivo | Resultado | Cumple |",
        "|:---|:---|:---|:---|:---|",
    ]
    for c in checks:
        actual = "sin datos" if c["actual"] is None else c["actual"]
        lines.append(f"| {c['scope']} | {c['metric']} | {symbol[c['metric']]} {c['target']} | {actual} | {'sí' if c['ok'] else 'no'} |")
    agg = stats["Aggregated"]
    lines += ["", f"Peticiones: {agg['requests']}, fallos: {agg['failures']}.",
              "", f"Veredicto: {'CUMPLE' if all(c['ok'] for c in checks) else 'NO CUMPLE'}."]
    return "\n".join(lines) + "\n"


def main(argv):
    if len(argv) != 4:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    stats = load_stats(argv[1])
    targets = json.loads(Path(argv[2]).read_text(encoding="utf8"))
    out = Path(argv[3])
    out.mkdir(parents=True, exist_ok=True)
    checks = evaluate(stats, targets)
    passed = all(c["ok"] for c in checks)
    (out / "summary.json").write_text(json.dumps({"passed": passed, "checks": checks}, indent=2), encoding="utf8")
    report = to_markdown(checks, stats, targets)
    (out / "summary.md").write_text(report, encoding="utf8")
    sys.stdout.reconfigure(encoding="utf-8")
    print(report)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
