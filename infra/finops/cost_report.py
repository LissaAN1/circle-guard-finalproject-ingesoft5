#!/usr/bin/env python3
"""HU-25: cost report per environment from AWS Cost Explorer.

Usage: cost_report.py --start 2026-11-01 --end 2026-11-21 [--profile circleguard]

The report groups the gross spend (credits and refunds excluded) by the Environment cost
allocation tag and by service, and states the credits separately. Cost Explorer charges
0.01 USD per API request and this script makes three, so each run costs about 0.03 USD.
The Environment tag only has data from the day it was activated in Billing; earlier spend
shows up as "sin etiqueta".
"""
import argparse
import sys
import json
import subprocess

NO_CREDITS = {"Not": {"Dimensions": {"Key": "RECORD_TYPE", "Values": ["Credit", "Refund"]}}}
CREDITS = {"Dimensions": {"Key": "RECORD_TYPE", "Values": ["Credit"]}}


def ce(args, start, end, profile, flt, group=None):
    cmd = [
        "aws", "ce", "get-cost-and-usage", "--time-period", f"Start={start},End={end}",
        "--granularity", "MONTHLY", "--metrics", "UnblendedCost", "--filter", json.dumps(flt),
        "--output", "json", "--region", "us-east-1",
    ]
    if group:
        cmd += ["--group-by", group]
    if profile:
        cmd += ["--profile", profile]
    out = subprocess.run(cmd, check=True, capture_output=True, text=True).stdout
    return json.loads(out)["ResultsByTime"]


def grouped(results):
    totals = {}
    for period in results:
        for g in period.get("Groups", []):
            key = g["Keys"][0]
            totals[key] = totals.get(key, 0.0) + float(g["Metrics"]["UnblendedCost"]["Amount"])
    return totals


def total(results):
    return sum(float(p["Total"]["UnblendedCost"]["Amount"]) for p in results)


def clean_tag(key):
    # Cost Explorer returns "Environment$dev"; an untagged cost is "Environment$".
    value = key.split("$", 1)[1] if "$" in key else key
    return value or "sin etiqueta"


def table(title, rows):
    lines = [f"### {title}", "", "| Concepto | USD |", "|:---|---:|"]
    for name, amount in sorted(rows.items(), key=lambda kv: -kv[1]):
        if abs(amount) >= 0.005:
            lines.append(f"| {name} | {amount:.2f} |")
    lines.append(f"| **Total** | **{sum(rows.values()):.2f}** |")
    return "\n".join(lines) + "\n"


def build(start, end, by_env, by_service, credits):
    gross = sum(by_service.values())
    parts = [
        f"# Reporte de costos del {start} al {end}",
        "",
        f"Gasto bruto: **{gross:.2f} USD**. Créditos aplicados: **{credits:.2f} USD**. "
        f"Neto cobrado: **{gross + credits:.2f} USD**.",
        "",
        table("Por ambiente (etiqueta Environment)", {clean_tag(k): v for k, v in by_env.items()}),
        table("Por servicio", by_service),
    ]
    return "\n".join(parts)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--start", required=True)
    p.add_argument("--end", required=True, help="exclusive end date")
    p.add_argument("--profile")
    sys.stdout.reconfigure(encoding="utf-8")
    a = p.parse_args()
    by_env = grouped(ce(None, a.start, a.end, a.profile, NO_CREDITS, "Type=TAG,Key=Environment"))
    by_service = grouped(ce(None, a.start, a.end, a.profile, NO_CREDITS, "Type=DIMENSION,Key=SERVICE"))
    credits = total(ce(None, a.start, a.end, a.profile, CREDITS))
    print(build(a.start, a.end, by_env, by_service, credits), end="")


if __name__ == "__main__":
    main()
