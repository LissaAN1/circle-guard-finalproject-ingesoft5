#!/usr/bin/env python3
"""HU-01: idempotently rotate SonarQube's initial admin password (on EC2 only).

No secrets are printed or passed on the command line. Uses only Python stdlib.
"""
import base64
import os
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

BASE = "http://127.0.0.1:9000"
SECRETS = Path("/opt/circleguard/sonarqube/sonar.secrets.env")


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


def main():
    wanted = secret("SONAR_ADMIN_PASSWORD")
    # Check application status, not merely an open TCP port.
    for _ in range(90):
        try:
            status, body = call("/api/system/status")
            if status == 200 and '"UP"' in body:
                break
        except (URLError, TimeoutError):
            pass
        time.sleep(5)
    else:
        raise RuntimeError("SonarQube did not become UP; examine container logs")

    if auth_valid(wanted):
        print("SonarQube already initialized; existing administrator password retained")
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


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
