#!/usr/bin/env python3
"""SonarQube bootstrap on the EC2 (HU-01, HU-05). Idempotent, Python stdlib only.

  configure.py          rotate the initial admin password (HU-01) and ensure the blocking quality gate (HU-05)
  configure.py --token  print the analysis token Jenkins uses (stdout only, nothing else); it is created once
                        and kept in the remote secrets file, so reruns do not change it

No secrets are passed on the command line.
"""
import base64
import json
import os
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

BASE = "http://127.0.0.1:9000"
SECRETS = Path("/opt/circleguard/sonarqube/sonar.secrets.env")

# HU-05: line coverage of the gated services (ci/units.conf, quality=gate) must be at least 60 %.
GATE_NAME = "CircleGuard"
# line_coverage, not "coverage": Sonar's "coverage" mixes lines and branches and is far lower than the
# line coverage HU-05 asks for (auth: 53.9 % vs 81.1 %).
GATE_METRIC, GATE_OP, GATE_THRESHOLD = "line_coverage", "LT", "60"
COVERAGE_METRICS = ("coverage", "line_coverage")
TOKEN_NAME = "jenkins-ci"
TOKEN_KEY = "SONAR_ANALYSIS_TOKEN"


def secret(name):
    for line in SECRETS.read_text(encoding="utf-8").splitlines():
        key, _, value = line.partition("=")
        if key == name:
            return value
    raise RuntimeError(f"Missing {name} in remote secrets file")


def call(path, username=None, password=None, data=None):
    headers = {}
    if username is not None:
        value = base64.b64encode(f"{username}:{password}".encode()).decode()
        headers["Authorization"] = "Basic " + value
    if data is not None:
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    request = Request(BASE + path, data=data, headers=headers)
    try:
        with urlopen(request, timeout=5) as response:
            return response.status, response.read().decode()
    except HTTPError as exc:
        return exc.code, exc.read().decode()


def auth_valid(password):
    status, body = call("/api/authentication/validate", "admin", password)
    return status == 200 and '"valid":true' in body.replace(" ", "")


def api(path, password, data=None):
    """Authenticated call as admin; form-encodes `data` (a dict) for POST."""
    body = urlencode(data).encode() if data is not None else None
    return call(path, "admin", password, body)


def ensure_quality_gate(password):
    """Create the blocking gate (coverage < 60 % fails) and make it the default. Safe to rerun."""
    status, body = api("/api/qualitygates/list", password)
    if status != 200:
        raise RuntimeError(f"Cannot list quality gates (HTTP {status})")
    gates = json.loads(body).get("qualitygates", [])
    if not any(g.get("name") == GATE_NAME for g in gates):
        status, _ = api("/api/qualitygates/create", password, {"name": GATE_NAME})
        if status != 200:
            raise RuntimeError(f"Cannot create quality gate (HTTP {status})")
        print(f"Quality gate {GATE_NAME} created")

    status, body = api("/api/qualitygates/show?" + urlencode({"name": GATE_NAME}), password)
    if status != 200:
        raise RuntimeError(f"Cannot read quality gate (HTTP {status})")
    conditions = json.loads(body).get("conditions", [])
    wanted = [c for c in conditions if c.get("metric") in COVERAGE_METRICS]
    exact = [c for c in wanted if c.get("metric") == GATE_METRIC
             and c.get("op") == GATE_OP and str(c.get("error")) == GATE_THRESHOLD]
    if not exact or len(wanted) > 1:
        for c in wanted:  # a stale threshold or an older metric would keep the gate wrong
            api("/api/qualitygates/delete_condition", password, {"id": c["id"]})
        status, _ = api("/api/qualitygates/create_condition", password, {
            "gateName": GATE_NAME, "metric": GATE_METRIC, "op": GATE_OP, "error": GATE_THRESHOLD})
        if status != 200:
            raise RuntimeError(f"Cannot set quality gate condition (HTTP {status})")
        print(f"Quality gate condition set: {GATE_METRIC} {GATE_OP} {GATE_THRESHOLD}")

    status, _ = api("/api/qualitygates/set_as_default", password, {"name": GATE_NAME})
    if status not in (200, 204):
        raise RuntimeError(f"Cannot set default quality gate (HTTP {status})")
    print(f"Quality gate {GATE_NAME} is the default (coverage >= {GATE_THRESHOLD} % required)")


def analysis_token(password):
    """Return the stored analysis token, creating it when missing or revoked; never logs it."""
    lines = SECRETS.read_text(encoding="utf-8").splitlines()
    stored = next((ln.partition("=")[2] for ln in lines if ln.startswith(TOKEN_KEY + "=")), "")
    status, body = api("/api/user_tokens/search", password)
    if status != 200:
        raise RuntimeError(f"Cannot list tokens (HTTP {status})")
    exists = any(t.get("name") == TOKEN_NAME for t in json.loads(body).get("userTokens", []))
    if stored and exists:
        return stored
    if exists:
        api("/api/user_tokens/revoke", password, {"name": TOKEN_NAME})
    status, body = api("/api/user_tokens/generate", password,
                       {"name": TOKEN_NAME, "type": "GLOBAL_ANALYSIS_TOKEN"})
    if status != 200:
        raise RuntimeError(f"Cannot generate analysis token (HTTP {status})")
    token = json.loads(body)["token"]
    kept = [ln for ln in lines if not ln.startswith(TOKEN_KEY + "=")] + [f"{TOKEN_KEY}={token}"]
    SECRETS.write_text(chr(10).join(kept) + chr(10), encoding="utf-8")
    return token


def wait_until_up():
    # Check application status, not merely an open TCP port.
    for _ in range(90):
        try:
            status, body = call("/api/system/status")
            if status == 200 and '"UP"' in body:
                return
        except (URLError, TimeoutError):
            pass
        time.sleep(5)
    raise RuntimeError("SonarQube did not become UP; examine container logs")


def main():
    wanted = secret("SONAR_ADMIN_PASSWORD")
    wait_until_up()
    if "--token" in sys.argv:
        print(analysis_token(wanted))
        return
    if auth_valid(wanted):
        print("SonarQube already initialized; existing administrator password retained")
        ensure_quality_gate(wanted)
        return
    if not auth_valid("admin"):
        raise RuntimeError("Neither generated nor initial admin credentials work; do not reset user data")

    form = urlencode({
        "login": "admin",
        "previousPassword": "admin",
        "password": wanted,
    }).encode()
    status, _ = call("/api/users/change_password", "admin", "admin", form)
    if status not in (200, 204):
        raise RuntimeError(f"SonarQube password rotation failed (HTTP {status})")
    if not auth_valid(wanted):
        raise RuntimeError("SonarQube did not accept the new password")
    print("SonarQube initial administrator password rotated successfully")
    ensure_quality_gate(wanted)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
