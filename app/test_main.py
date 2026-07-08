"""
Unit tests for the GenAI app - the CI gate of our pipeline.
-----------------------------------------------------------
These run on every push/PR *before* any deployment step. If any test fails,
GitHub Actions stops the workflow and the broken code never reaches Azure.
(Session 5 key takeaway: "Testing is mandatory - if tests fail, deployment
never happens.")

They deliberately avoid calling the real Gemini API: no key is needed, so the
same tests run identically on a laptop and inside a clean CI runner.

Run locally:
    pip install -r requirements.txt -r requirements-dev.txt
    pytest
"""

from fastapi.testclient import TestClient

import main

client = TestClient(main.app)


def test_root_lists_endpoints():
    resp = client.get("/")
    assert resp.status_code == 200
    body = resp.json()
    assert "endpoints" in body
    assert body["endpoints"]["health"] == "/health"


def test_health_reports_status():
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    # "healthy" when a key is configured, "degraded" when not - both are valid
    # in CI, where no real key is present.
    assert body["status"] in ("healthy", "degraded")
    assert "api_key_configured" in body


def test_generate_rejects_empty_prompt():
    # Pydantic validation must reject an empty prompt before any model call.
    resp = client.post("/api/generate", json={"prompt": ""})
    assert resp.status_code == 422


def test_generate_rejects_bad_temperature():
    resp = client.post("/api/generate", json={"prompt": "hi", "temperature": 5.0})
    assert resp.status_code == 422


def test_history_starts_readable():
    resp = client.get("/api/history")
    assert resp.status_code == 200
    body = resp.json()
    assert "total_chats" in body
    assert isinstance(body["history"], list)
