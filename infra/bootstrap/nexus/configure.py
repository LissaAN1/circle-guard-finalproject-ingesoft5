#!/usr/bin/env python3
"""HU-01: initial Nexus security and hosted Docker registry via documented REST API.

Run as root ONLY on the Nexus EC2. No external dependencies or secrets in Git.
Existing users, roles, images and passwords are preserved; mismatches fail closed.
"""
import base64
import json
import subprocess
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

BASE = "http://127.0.0.1:8081/service/rest/v1"
REPO = "circleguard-docker"
SECRETS = Path("/opt/circleguard/nexus/nexus.secrets.env")


def read_secrets():
    result = {}
    for line in SECRETS.read_text(encoding="utf-8").splitlines():
        if line.strip():
            key, sep, value = line.partition("=")
            if not sep:
                raise RuntimeError("Malformed Nexus secrets file")
            result[key] = value
    needed = ("NEXUS_ADMIN_PASSWORD", "NEXUS_PUBLISHER_PASSWORD", "NEXUS_READER_PASSWORD")
    if any(not result.get(k) for k in needed):
        raise RuntimeError("Remote Nexus secrets file lacks required keys")
    return result


def api(path, password, method="GET", payload=None, text=False):
    raw = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        if text:
            raw = payload.encode("utf-8")
            headers["Content-Type"] = "text/plain"
        else:
            raw = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
    auth = base64.b64encode(f"admin:{password}".encode()).decode()
    headers["Authorization"] = "Basic " + auth
    request = Request(BASE + path, data=raw, method=method, headers=headers)
    try:
        with urlopen(request, timeout=15) as response:
            output = response.read().decode()
            if text or not output:
                body = output
            else:
                try:
                    body = json.loads(output)
                except json.JSONDecodeError:
                    body = output
            return response.status, body
    except HTTPError as exc:
        # Never print request body: it can contain a secret.
        return exc.code, None


def checked(path, password, method="GET", payload=None, text=False, expected=(200, 201, 204)):
    code, result = api(path, password, method, payload, text)
    if code not in expected:
        raise RuntimeError(f"Nexus API {method} {path} returned HTTP {code}")
    return result


def admin_credentials(secrets):
    wanted = secrets["NEXUS_ADMIN_PASSWORD"]
    code, _ = api("/security/users", wanted)
    if code == 200:
        return wanted
    try:
        old = subprocess.check_output(
            ["docker", "exec", "circleguard-nexus", "cat", "/nexus-data/admin.password"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
    except subprocess.CalledProcessError as exc:
        raise RuntimeError("Admin credentials differ from the saved secret and bootstrap password is unavailable") from exc
    code, _ = api("/security/users", old)
    if code != 200:
        raise RuntimeError("Initial Nexus admin password cannot authenticate; finish onboarding or investigate logs")
    checked("/security/users/admin/change-password", old, "PUT", wanted, text=True)
    code, _ = api("/security/users", wanted)
    if code != 200:
        raise RuntimeError("Nexus did not accept the new administrative password")
    print("Nexus admin password rotated; secret retained on EC2")
    return wanted


def ensure_security(password):
    settings = checked("/security/anonymous", password)
    if settings.get("enabled", False):
        checked("/security/anonymous", password, "PUT", {
            "enabled": False, "userId": "anonymous", "realmName": "NexusAuthorizingRealm"
        })
        print("Anonymous access disabled")

    realms = checked("/security/realms/active", password)
    if "DockerToken" not in realms:
        checked("/security/realms/active", password, "PUT", [*realms, "DockerToken"])
        print("Docker Bearer Token realm enabled")


def ensure_repository(password):
    path = f"/repositories/docker/hosted/{REPO}"
    code, data = api(path, password)
    if code == 404:
        checked("/repositories/docker/hosted", password, "POST", {
            "name": REPO,
            "online": True,
            "storage": {
                "blobStoreName": "default",
                "strictContentTypeValidation": True,
                "writePolicy": "ALLOW_ONCE",
            },
            "docker": {"v1Enabled": False, "forceBasicAuth": True, "httpPort": 8082},
        })
        print("Created immutable Docker hosted repository")
        data = checked(path, password)
    elif code != 200:
        raise RuntimeError(f"Could not inspect Docker repository (HTTP {code})")
    if data.get("docker", {}).get("httpPort") != 8082:
        raise RuntimeError("Existing Docker repository connector is not on 8082; refusing to overwrite")
    if data.get("storage", {}).get("writePolicy", "").upper() != "ALLOW_ONCE":
        raise RuntimeError("Existing Docker repository writePolicy is not ALLOW_ONCE; refusing to overwrite")


def ensure_role(password, role, privileges):
    path = f"/security/roles/{role}"
    code, existing = api(path, password)
    if code == 404:
        checked("/security/roles", password, "POST", {
            "id": role, "name": role,
            "description": "CircleGuard HU-01 restricted Docker repository service role",
            "privileges": privileges, "roles": [],
        })
        print(f"Created role {role}")
    elif code == 200:
        if not set(privileges).issubset(set(existing.get("privileges", []))):
            raise RuntimeError(f"Existing role {role} lacks expected permissions; refusing silent changes")
    else:
        raise RuntimeError(f"Could not inspect role {role} (HTTP {code})")


def ensure_user(password, user_id, user_password, role, label):
    accounts = checked("/security/users", password)
    found = next((u for u in accounts if u.get("userId") == user_id), None)
    if found:
        if role not in found.get("roles", []):
            raise RuntimeError(f"User {user_id} exists but lacks {role}; refusing silent changes")
        return
    checked("/security/users", password, "POST", {
        "userId": user_id,
        "firstName": "CircleGuard", "lastName": label,
        "emailAddress": f"{user_id}@example.invalid",
        "password": user_password, "status": "active", "roles": [role],
    })
    print(f"Created restricted user {user_id}")


def main():
    secrets = read_secrets()
    for _ in range(90):
        try:
            code, _ = api("/status", secrets["NEXUS_ADMIN_PASSWORD"])
            if code in (200, 401, 403):
                break
        except (URLError, TimeoutError, ValueError):
            pass
        time.sleep(5)
    else:
        raise RuntimeError("Nexus API did not start; inspect docker logs circleguard-nexus")

    password = admin_credentials(secrets)
    ensure_security(password)
    ensure_repository(password)
    prefix = f"nx-repository-view-docker-{REPO}-"
    ensure_role(password, "circleguard-publisher", [
        prefix + "browse", prefix + "read", prefix + "add", prefix + "edit"
    ])
    ensure_role(password, "circleguard-reader", [prefix + "browse", prefix + "read"])
    ensure_user(password, "cg-publisher", secrets["NEXUS_PUBLISHER_PASSWORD"], "circleguard-publisher", "Publisher")
    ensure_user(password, "cg-reader", secrets["NEXUS_READER_PASSWORD"], "circleguard-reader", "Reader")
    print("Nexus Docker hosted repository, realms, users and roles are ready")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
