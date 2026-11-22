#!/usr/bin/env python3
"""HU-18: genera los dashboards de Grafana (uno por servicio y uno de negocio).

Uso:  python observability/grafana/generate_dashboards.py
"""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parent / "dashboards"
SERVICES = ["auth", "identity", "promotion", "form", "gateway", "dashboard", "file", "notification"]
PROM = {"type": "prometheus", "uid": "prometheus"}
LOKI = {"type": "loki", "uid": "loki"}
SIN_ACTUATOR = 'uri!~"/actuator.*"'  # ignora las peticiones de salud
LEVEL_VAR = {
    "name": "level", "label": "Nivel de log", "type": "custom",
    "query": "ERROR,WARN,INFO,DEBUG", "multi": True, "includeAll": True, "allValue": ".*",
    "current": {"selected": True, "text": ["All"], "value": ["$__all"]},
}


def timeseries(pid, title, queries, unit, x, y, w, h):
    targets = [{"datasource": PROM, "expr": expr, "legendFormat": legend, "refId": chr(65 + i)}
               for i, (expr, legend) in enumerate(queries)]
    return {
        "id": pid, "type": "timeseries", "title": title, "datasource": PROM,
        "gridPos": {"x": x, "y": y, "w": w, "h": h}, "targets": targets,
        "fieldConfig": {"defaults": {"unit": unit, "custom": {"fillOpacity": 10}}, "overrides": []},
        "options": {"legend": {"displayMode": "list", "placement": "bottom"}, "tooltip": {"mode": "multi"}},
    }


def dashboard(uid, title, panels, variables=()):
    return {
        "uid": uid, "title": title, "tags": ["circleguard"], "timezone": "browser",
        "schemaVersion": 39, "version": 1, "editable": True, "refresh": "30s",
        "time": {"from": "now-1h", "to": "now"},
        "templating": {"list": list(variables)}, "annotations": {"list": []}, "panels": panels,
    }


def service_dashboard(svc):
    app = f"circleguard-{svc}-service"
    sel = f'application="{app}"'
    estado = {
        "id": 1, "type": "stat", "title": "Estado del servicio", "datasource": PROM,
        "gridPos": {"x": 0, "y": 0, "w": 4, "h": 8},
        "targets": [{"datasource": PROM, "refId": "A",
                     "expr": f'max(up{{job="circleguard-services", {sel}}}) or vector(0)'}],
        "fieldConfig": {"defaults": {
            "mappings": [{"type": "value", "options": {"0": {"text": "DOWN"}, "1": {"text": "UP"}}}],
            "color": {"mode": "thresholds"},
            "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None},
                                                        {"color": "green", "value": 1}]},
        }, "overrides": []},
        "options": {"colorMode": "background", "graphMode": "none",
                    "reduceOptions": {"calcs": ["lastNotNull"]}},
    }
    logs = {
        "id": 5, "type": "logs", "title": f"Logs de {app}", "datasource": LOKI,
        "gridPos": {"x": 0, "y": 16, "w": 24, "h": 12},
        "targets": [{"datasource": LOKI, "refId": "A", "expr": f'{{service="{svc}", level=~"$level"}}'}],
        "options": {"showTime": True, "wrapLogMessage": True, "sortOrder": "Descending",
                    "enableLogDetails": True},
    }
    panels = [
        estado,
        timeseries(2, "Latencia p95", [(
            f"histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{{{sel}, {SIN_ACTUATOR}}}[5m])))",
            "p95")], "s", 4, 0, 10, 8),
        timeseries(3, "Errores 5xx por segundo", [(
            f'sum(rate(http_server_requests_seconds_count{{{sel}, outcome="SERVER_ERROR", {SIN_ACTUATOR}}}[5m])) or vector(0)',
            "errores")], "reqps", 14, 0, 10, 8),
        timeseries(4, "Memoria de la JVM", [
            (f'sum(jvm_memory_used_bytes{{{sel}, area="heap"}})', "heap"),
            (f'sum(jvm_memory_used_bytes{{{sel}, area="nonheap"}})', "non-heap"),
        ], "bytes", 0, 8, 24, 8),
        logs,
    ]
    return dashboard(f"cg-{svc}", f"CircleGuard · {svc}", panels, [LEVEL_VAR])


def business_dashboard():
    panels = [
        timeseries(1, "Promociones por minuto", [
            ("sum by (status) (rate(circleguard_promotions_total[5m])) * 60", "{{status}}")],
            "short", 0, 0, 12, 8),
        timeseries(2, "Check-ins por minuto según resultado", [
            ("sum by (result) (rate(circleguard_checkins_total[5m])) * 60", "{{result}}")],
            "short", 12, 0, 12, 8),
        timeseries(3, "Tiempo de contención (p95)", [
            ("histogram_quantile(0.95, sum by (le) (rate(circleguard_containment_duration_seconds_bucket[5m])))",
             "p95")], "s", 0, 8, 24, 8),
    ]
    return dashboard("cg-business", "CircleGuard · Negocio", panels)


def build_all():
    files = {f"circleguard-{s}.json": service_dashboard(s) for s in SERVICES}
    files["circleguard-business.json"] = business_dashboard()
    return files


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, content in build_all().items():
        (OUT / name).write_text(json.dumps(content, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print("generado", OUT / name)


if __name__ == "__main__":
    main()