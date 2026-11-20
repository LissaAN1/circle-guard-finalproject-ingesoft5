#!/usr/bin/env python3
"""HU-25: estimate what the scale-to-zero schedule saves in the non-production environments.

Usage: savings.py [--price 0.09576] [--dev-nodes 1] [--stage-nodes 2] [--start 7] [--stop 20]

Compute is billed per hour while an instance runs, so stopping the nodes outside working
hours cuts that part of the bill. EBS volumes keep billing while the instances are stopped,
so they are reported as a fixed cost that the schedule does not touch.
"""
import argparse
import sys

HOURS_PER_MONTH = 730.0  # 8760 / 12
WEEKS_PER_MONTH = 52.0 / 12


def scheduled_hours(start: int, stop: int) -> float:
    """Hours per month the nodes run with a working-day start and a daily stop."""
    if not 0 <= start < stop <= 24:
        raise ValueError("start must be before stop, both between 0 and 24")
    return (stop - start) * 5 * WEEKS_PER_MONTH


def estimate(price: float, nodes: dict, start: int, stop: int, volume_gb: int = 30, gb_price: float = 0.08):
    on_hours = scheduled_hours(start, stop)
    rows = []
    for env, count in nodes.items():
        always = count * price * HOURS_PER_MONTH
        scheduled = count * price * on_hours
        rows.append({
            "env": env,
            "nodes": count,
            "always_on": always,
            "scheduled": scheduled,
            "saving": always - scheduled,
            "volumes": count * volume_gb * gb_price,
        })
    return {"on_hours": on_hours, "rows": rows}


def to_markdown(result, price, start, stop):
    lines = [
        f"Precio de cómputo: {price:.5f} USD por hora y nodo. Horario: {start:02d}:00 a {stop:02d}:00 de lunes a viernes "
        f"({result['on_hours']:.0f} horas encendido al mes frente a {HOURS_PER_MONTH:.0f} si estuviera siempre encendido).",
        "",
        "| Ambiente | Nodos | Siempre encendido | Con horario | Ahorro | Discos (fijo) |",
        "|:---|---:|---:|---:|---:|---:|",
    ]
    total = {"always_on": 0.0, "scheduled": 0.0, "saving": 0.0, "volumes": 0.0}
    for r in result["rows"]:
        lines.append(
            f"| {r['env']} | {r['nodes']} | {r['always_on']:.2f} USD | {r['scheduled']:.2f} USD | "
            f"{r['saving']:.2f} USD | {r['volumes']:.2f} USD |"
        )
        for k in total:
            total[k] += r[k]
    pct = 100 * total["saving"] / total["always_on"] if total["always_on"] else 0
    lines.append(
        f"| **Total** | | **{total['always_on']:.2f} USD** | **{total['scheduled']:.2f} USD** | "
        f"**{total['saving']:.2f} USD** | **{total['volumes']:.2f} USD** |"
    )
    lines += ["", f"Ahorro de cómputo: {pct:.0f} % al mes, valores en USD por mes."]
    return "\n".join(lines) + "\n"


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--price", type=float, default=0.09576, help="USD per node hour (m7i-flex.large, us-east-1)")
    p.add_argument("--dev-nodes", type=int, default=1)
    p.add_argument("--stage-nodes", type=int, default=2)
    p.add_argument("--start", type=int, default=7)
    p.add_argument("--stop", type=int, default=20)
    sys.stdout.reconfigure(encoding="utf-8")
    a = p.parse_args()
    result = estimate(a.price, {"dev": a.dev_nodes, "stage": a.stage_nodes}, a.start, a.stop)
    print(to_markdown(result, a.price, a.start, a.stop), end="")


if __name__ == "__main__":
    main()
