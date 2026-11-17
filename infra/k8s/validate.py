#!/usr/bin/env python3
"""Offline checks of the rendered manifests of every environment (no cluster needed).

Usage: python infra/k8s/validate.py   (needs kubectl for `kubectl kustomize`)
"""
import re, subprocess, sys
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
APPS = {"auth": 8180, "identity": 8083, "promotion": 8088, "form": 8086, "gateway": 8087,
        "dashboard": 8084, "file": 8085, "notification": 8082, "web": 8080}
MIDDLEWARE = {"postgres": 5432, "neo4j": 7687, "zookeeper": 2181, "kafka": 9092, "redis": 6379, "openldap": 389}
SECRET_KEYS = {"DB_USER", "DB_PASSWORD", "NEO4J_PASSWORD", "LDAP_ADMIN_PASSWORD", "REDIS_PASSWORD",
               "JWT_SECRET", "QR_SECRET", "VAULT_SECRET", "VAULT_SALT", "VAULT_HASH_SALT"}
HPA_BOUNDS = {"dev": (1, 2), "stage": (1, 3), "prod": (2, 5)}  # (min, max) replicas
failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


for env in ("dev", "stage", "prod"):
    out = subprocess.run(["kubectl", "kustomize", str(HERE / "overlays" / env)], capture_output=True, text=True)
    if out.returncode:
        failures.append(f"{env}: kustomize failed: {out.stderr.strip()}")
        continue
    docs = [d for d in yaml.safe_load_all(out.stdout) if d]
    ns = f"circleguard-{env}"
    kinds = {}
    for d in docs:
        kinds.setdefault(d["kind"], {})[d["metadata"]["name"]] = d
        if d["kind"] != "Namespace":
            check(d["metadata"].get("namespace") == ns, f"{env}: {d['kind']}/{d['metadata']['name']} not in {ns}")
    check(ns in kinds.get("Namespace", {}), f"{env}: namespace {ns} missing")
    services = kinds.get("Service", {})
    for name, port in {**APPS, **MIDDLEWARE}.items():
        workload = kinds.get("Deployment", {}).get(name) or kinds.get("StatefulSet", {}).get(name)
        check(workload is not None, f"{env}: workload {name} missing")
        check(name in services, f"{env}: Service {name} missing")
        if workload is None:
            continue
        c = workload["spec"]["template"]["spec"]["containers"][0]
        if name in APPS:
            check(c["ports"][0]["containerPort"] == port, f"{env}: {name} port != {port}")
            for probe in ("startupProbe", "readinessProbe", "livenessProbe"):
                check(probe in c, f"{env}: {name} lacks {probe}")
                if name != "web" and probe in c:
                    check(c[probe]["httpGet"]["path"] == "/actuator/health", f"{env}: {name} {probe} is not on Actuator")
            check("replicas" not in workload["spec"], f"{env}: {name} fixes replicas; the HPA must own the count")
            # HU-12: one CPU-based HPA per service and for the web client.
            hpa = kinds.get("HorizontalPodAutoscaler", {}).get(name)
            check(hpa is not None, f"{env}: HPA for {name} missing")
            if hpa:
                spec = hpa["spec"]
                check(spec["scaleTargetRef"]["kind"] == "Deployment" and spec["scaleTargetRef"]["name"] == name,
                      f"{env}: HPA {name} targets the wrong workload")
                check(any(m.get("resource", {}).get("name") == "cpu" for m in spec["metrics"]), f"{env}: HPA {name} is not CPU based")
                check((spec["minReplicas"], spec["maxReplicas"]) == HPA_BOUNDS[env], f"{env}: HPA {name} bounds != {HPA_BOUNDS[env]}")
                check("requests" in c.get("resources", {}) and "cpu" in c["resources"]["requests"], f"{env}: {name} has no CPU request for its HPA")
        check("limits" in c.get("resources", {}), f"{env}: {name} lacks resource limits")
    for name, d in kinds.get("Deployment", {}).items():
        for e in d["spec"]["template"]["spec"]["containers"][0].get("env", []):
            ref = e.get("valueFrom", {}).get("secretKeyRef")
            if ref:
                check(ref["name"] == "circleguard-secrets" and ref["key"] in SECRET_KEYS,
                      f"{env}: {name} reads unknown secret key {ref}")
            else:
                check(not re.search(r"(PASSWORD|SECRET|SALT)", e["name"]) or "valueFrom" in e,
                      f"{env}: {name} has a literal value for {e['name']}")
    check("Secret" not in kinds, f"{env}: a Secret is committed; create it with secrets.sh")
    # Hostnames the web nginx proxies to must exist as Services.
    for host in ("auth", "identity", "promotion", "form", "gateway"):
        check(host in services, f"{env}: nginx upstream {host} has no Service")
    # HU-12: the Ingress exposes the web client and the gateway through Traefik (k3s).
    ingresses = kinds.get("Ingress", {})
    routes = {}
    for ing in ingresses.values():
        check(ing["spec"].get("ingressClassName") == "traefik", f"{env}: Ingress {ing['metadata']['name']} is not for traefik")
        for rule in ing["spec"]["rules"]:
            for p in rule["http"]["paths"]:
                routes[p["path"]] = p["backend"]["service"]["name"]
    check(routes.get("/") == "web", f"{env}: Ingress does not expose the web client on /")
    check(routes.get("/gateway") == "gateway", f"{env}: Ingress does not expose the gateway on /gateway")
    gw = ingresses.get("circleguard-gateway")
    if gw:
        want = f"{ns}-strip-gateway@kubernetescrd"
        check(gw["metadata"]["annotations"].get("traefik.ingress.kubernetes.io/router.middlewares") == want,
              f"{env}: gateway Ingress middleware is not {want}")
    check("strip-gateway" in kinds.get("Middleware", {}), f"{env}: Middleware strip-gateway missing")
    print(f"{env}: {len(docs)} objects, namespace {ns}")

# Scripts: lib.sh lists the workloads deploy.sh waits for, and the secrets never
# travel as command-line arguments.
lib = (HERE / "lib.sh").read_text()
deploy = (HERE / "deploy.sh").read_text()
secrets = (HERE / "secrets.sh").read_text()
sts = re.search(r"WORKLOAD_STATEFULSETS=\((.*?)\)", lib).group(1).split()
dep = re.search(r"WORKLOAD_DEPLOYMENTS=\((.*?)\)", lib).group(1).split()
check(set(dep) == set(APPS), "lib.sh WORKLOAD_DEPLOYMENTS differs from the application Deployments")
check(set(sts) == set(MIDDLEWARE), "lib.sh WORKLOAD_STATEFULSETS differs from the middleware StatefulSets")
check('rollout status "statefulset/$app"' in deploy and 'rollout status "deployment/$app"' in deploy,
      "deploy.sh must wait for each workload by name")
check(not re.search(r"rollout status (statefulset|deployment) --", deploy), "deploy.sh has a rollout status without a resource")
check("--from-literal" not in secrets and "--from-file" in secrets, "secrets.sh must not pass secret values as arguments")
for name, text in (("deploy.sh", deploy), ("secrets.sh", secrets)):
    check("select_cluster" in text, f"{name} does not pin the cluster with select_cluster")
    check(not re.search(r"^\s*kubectl", text, re.M), f"{name} calls kubectl without the pinned context (use kc)")
print("scripts: workloads, secrets and cluster selection checked")

if failures:
    print("\n".join("FAIL " + f for f in failures))
    sys.exit(1)
print("OK: all environments consistent")
