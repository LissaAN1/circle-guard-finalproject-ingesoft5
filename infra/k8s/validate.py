#!/usr/bin/env python3
"""Offline checks of the rendered manifests of every environment (no cluster needed).

Usage: python infra/k8s/validate.py   (needs kubectl for `kubectl kustomize`)
"""
import re, subprocess, sys, tempfile
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
APPS = {"auth": 8180, "identity": 8083, "promotion": 8088, "form": 8086, "gateway": 8087,
        "dashboard": 8084, "file": 8085, "notification": 8082, "web": 8080}
NO_ACTUATOR = {"dashboard", "file", "notification"}
MIDDLEWARE = {"postgres": 5432, "neo4j": 7687, "zookeeper": 2181, "kafka": 9092, "redis": 6379, "openldap": 389}
SECRET_KEYS = {"DB_USER", "DB_PASSWORD", "NEO4J_PASSWORD", "LDAP_ADMIN_PASSWORD", "REDIS_PASSWORD",
               "JWT_SECRET", "QR_SECRET", "VAULT_SECRET", "VAULT_SALT", "VAULT_HASH_SALT"}
HPA_BOUNDS = {"dev": (1, 2), "stage": (1, 3), "prod": (2, 5)}  # (min, max) replicas
FEATURE_TOGGLES = {"FEATURE_DENY_SUSPECT_ENTRY": "gateway"}  # HU-15: toggle -> Deployment that reads it
failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


def render(path):
    out = subprocess.run(["kubectl", "kustomize", str(path)], capture_output=True, text=True)
    return out.returncode, out.stderr.strip(), [d for d in yaml.safe_load_all(out.stdout) if d] if not out.returncode else []


def by_kind(docs):
    kinds = {}
    for d in docs:
        kinds.setdefault(d["kind"], {})[d["metadata"]["name"]] = d
    return kinds


for env in ("dev", "stage", "prod"):
    code, err, docs = render(HERE / "overlays" / env)
    if code:
        failures.append(f"{env}: kustomize failed: {err}")
        continue
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
                if name in NO_ACTUATOR and probe in c:
                    # These services do not include Spring Boot Actuator yet.
                    check("tcpSocket" in c[probe], f"{env}: {name} {probe} must be a TCP check")
                elif name != "web" and probe in c:
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
    # HU-15: each environment sets its feature toggles in the ConfigMap and the service reads them from it.
    config = kinds.get("ConfigMap", {}).get("circleguard-config", {}).get("data", {})
    for toggle, app in FEATURE_TOGGLES.items():
        check(config.get(toggle) in ("true", "false"), f"{env}: ConfigMap circleguard-config lacks {toggle}=true|false")
        workload = kinds.get("Deployment", {}).get(app)
        envs = workload["spec"]["template"]["spec"]["containers"][0].get("env", []) if workload else []
        ref = next((e.get("valueFrom", {}).get("configMapKeyRef") for e in envs if e["name"] == toggle), None)
        check(ref == {"name": "circleguard-config", "key": toggle}, f"{env}: {app} does not read {toggle} from the ConfigMap")
    print(f"{env}: {len(docs)} objects, namespace {ns}")

# HU-15: flipping a toggle in the ConfigMap changes only the ConfigMap. Every Deployment (and so every
# image) renders exactly the same, which is why the change needs a restart but no new image.
with tempfile.TemporaryDirectory(dir=HERE) as tmp:
    flipped = {t: "false" for t in FEATURE_TOGGLES}
    literals = ", ".join(f"{k}={v}" for k, v in flipped.items())
    (Path(tmp) / "kustomization.yaml").write_text(
        "resources:\n  - ../overlays/dev\n"
        "configMapGenerator:\n  - name: circleguard-config\n    behavior: merge\n"
        f"    literals: [{literals}]\n"
        "    options: {disableNameSuffixHash: true}\n")
    base_code, _, base_docs = render(HERE / "overlays" / "dev")
    flip_code, err, flip_docs = render(tmp)
    check(not base_code and not flip_code, f"toggle flip: kustomize failed: {err}")
    if not base_code and not flip_code:
        before, after = by_kind(base_docs), by_kind(flip_docs)
        check(before.get("Deployment") == after.get("Deployment"), "toggle flip: a Deployment changed with the ConfigMap")
        cm_after = after["ConfigMap"]["circleguard-config"]["data"]
        check(all(cm_after.get(k) == v for k, v in flipped.items()), "toggle flip: the ConfigMap did not change")
        print("toggles: flipping the ConfigMap leaves every Deployment and image unchanged")

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
