"""AI coach: PII-free context assembly, status, the chat endpoint (Gemini mocked),
and the unconfigured/auth guards."""
from app.coach import build_context, compose_system


def test_build_context_structured_and_pii_free():
    ctx = build_context(
        [],
        habits=[{"title": "Sleep 8h", "category": "sleep", "done_today": True, "streak": 3}],
        profile={"age": 28, "gender": "male", "weightKg": 80},
    )
    assert "Sleep 8h" in ctx and "[sleep]" in ctx and "streak 3" in ctx
    assert "age 28" in ctx and "male" in ctx
    assert "No logged or synced data yet" in ctx
    # No identifiers leak into the model context.
    assert "@" not in ctx and "user_id" not in ctx


def test_compose_system_wraps_prompt_and_data():
    s = compose_system([], habits=[], profile=None)
    assert "AI coach" in s and "USER DATA" in s and "not a clinician" in s


def test_coach_status_unconfigured(client):
    r = client.get("/me/coach/status")
    assert r.status_code == 200 and r.json()["configured"] is False


def test_coach_chat_503_when_unconfigured(client):
    assert client.post("/me/coach/chat", json={"message": "hi"}).status_code == 503


def test_coach_chat_sees_real_data(client, monkeypatch):
    from app.integrations.gemini import client as gem
    monkeypatch.setattr(gem, "configured", lambda: True)
    captured = {}

    def fake_generate(system, turns, **kw):
        captured["system"] = system
        captured["turns"] = turns
        return "Prioritise your weakest lift this week."

    monkeypatch.setattr(gem, "generate", fake_generate)

    client.post("/me/samples", json=[
        {"metric_id": "bench", "ts": "2026-06-01T08:00:00", "bodyweight_at_ts": 80,
         "value": 100, "source": "manual", "source_id": "b1"}])

    r = client.post("/me/coach/chat", json={
        "message": "How am I doing?",
        "habits": [{"title": "Train", "done_today": True}]})
    assert r.status_code == 200
    assert r.json()["reply"] == "Prioritise your weakest lift this week."
    # The model was given the user's real ranks + habits and the new message.
    assert "Overall rank" in captured["system"] and "Train" in captured["system"]
    assert captured["turns"][-1] == {"role": "user", "text": "How am I doing?"}


def test_coach_requires_auth():
    from fastapi.testclient import TestClient
    from app.main import app
    with TestClient(app) as c:
        assert c.post("/me/coach/chat", json={"message": "hi"}).status_code == 401
