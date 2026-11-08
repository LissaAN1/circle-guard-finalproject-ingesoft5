#!/usr/bin/env python3
"""Read-only checks of the HU-02 Compose configuration. Requires PyYAML."""
from pathlib import Path
import re
import sys
import yaml

ROOT = Path(__file__).resolve().parent
CORE = ("auth", "identity", "promotion", "form", "gateway")
MIDDLEWARE = ("postgres", "neo4j", "zookeeper", "kafka", "redis", "openldap")
config = yaml.safe_load((ROOT / "compose.base.yaml").read_text(encoding="utf-8"))
services = config["services"]
assert set(CORE + MIDDLEWARE + ("web",)) == set(services), "Unexpected or missing services"
for svc in CORE:
    conf = services[svc]
    assert "build" not in conf, svc
    assert "/actuator/health" in str(conf["healthcheck"]["test"]), svc
    assert "${REGISTRY:" in conf["image"] and "${APP_VERSION:" in conf["image"], svc
for svc in ("web",) + MIDDLEWARE:
    assert "build" not in services[svc], svc
assert services["web"]["ports"] == ["${WEB_BIND_IP:-127.0.0.1}:80:8080"]
for env in ("dev", "stage", "prod"):
    overlay = yaml.safe_load((ROOT / f"compose.{env}.yaml").read_text(encoding="utf-8"))
    assert overlay["name"] == f"circleguard-{env}"
assert (ROOT / "init-db.sql").exists()
print("PASS: three environments, 12 services, five Actuator checks, no build instructions")
