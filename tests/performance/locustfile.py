"""HU-21: load scenarios for the two critical CircleGuard flows, run against stage.

Gate validation: a healthy user asks auth-service for a short-lived QR token and the
gate validates it in gateway-service. The decision must be GREEN.
Survey submission: a user reads the active questionnaire in form-service and submits
it answering NO to every question, so the load never changes anyone's health status.

Both flows use the dedicated E2E survey account (E2E_USERNAME / E2E_PASSWORD). Tokens,
passwords and response bodies are never logged.
"""
import json
import os
import random

from locust import HttpUser, between, task

LOGIN = "/auth/api/v1/auth/login"
QR = "/auth/api/v1/auth/qr/generate"
GATE = "/gateway/api/v1/gate/validate"
ACTIVE = "/form/api/v1/questionnaires/active"
SURVEYS = "/form/api/v1/surveys"


def credentials():
    username, password = os.environ.get("E2E_USERNAME"), os.environ.get("E2E_PASSWORD")
    if not username or not password:
        raise RuntimeError("E2E_USERNAME and E2E_PASSWORD are required")
    return username, password


def negative_answers(questionnaire):
    """Answer NO (or the first option) to every question: a healthy, side-effect free report."""
    answers = {}
    for q in questionnaire.get("questions") or []:
        if q.get("type") == "YES_NO":
            answers[q["id"]] = "NO"
        elif q.get("options"):
            # options is JSONB: a list, a JSON-encoded list or a comma-separated string.
            raw = q["options"]
            if isinstance(raw, str):
                try:
                    raw = json.loads(raw)
                except ValueError:
                    raw = raw.split(",")
            options = [str(o).strip() for o in (raw if isinstance(raw, list) else [raw]) if str(o).strip()]
            answers[q["id"]] = options[0] if options else "NONE"
        else:
            answers[q["id"]] = "NONE"
    return answers


class CampusUser(HttpUser):
    wait_time = between(1, 3)

    def on_start(self):
        username, password = credentials()
        with self.client.post(LOGIN, json={"username": username, "password": password},
                              name="auth: login", catch_response=True) as r:
            data = r.json() if r.ok else {}
            if not data.get("token") or not data.get("anonymousId"):
                r.failure(f"login failed: HTTP {r.status_code}")
                self.stop()
                return
            self.token, self.anonymous_id = data["token"], data["anonymousId"]
        self.questionnaire = None

    @task(3)
    def gate_validation(self):
        with self.client.get(QR, headers={"Authorization": f"Bearer {self.token}"},
                             name="gate: qr generate", catch_response=True) as r:
            qr = (r.json() if r.ok else {}).get("qrToken")
            if not qr:
                r.failure(f"no QR token: HTTP {r.status_code}")
                return
        with self.client.post(GATE, json={"token": qr}, name="gate: validate",
                              catch_response=True) as r:
            decision = r.json() if r.ok else {}
            if decision.get("valid") is not True or decision.get("status") != "GREEN":
                r.failure(f"healthy user not admitted: HTTP {r.status_code} status={decision.get('status')}")

    @task(1)
    def survey_submission(self):
        with self.client.get(ACTIVE, name="survey: active questionnaire", catch_response=True) as r:
            if not r.ok or not (r.json() or {}).get("questions"):
                r.failure(f"no active questionnaire: HTTP {r.status_code}")
                return
            self.questionnaire = r.json()
        body = {"anonymousId": self.anonymous_id, "responses": negative_answers(self.questionnaire),
                "attachmentPath": None, "hasFever": False, "hasCough": False}
        with self.client.post(SURVEYS, json=body, name="survey: submit", catch_response=True) as r:
            if not r.ok:
                r.failure(f"survey rejected: HTTP {r.status_code}")


# Deterministic think time in CI when a seed is given (reproducible runs).
if os.environ.get("CG_LOCUST_SEED"):
    random.seed(int(os.environ["CG_LOCUST_SEED"]))
