"""AI weekly planner: defensive roster parsing + the /me/coach/plan endpoint."""
from app.planner import PLAN_PROMPT, parse_plan


def test_parse_plan_happy_path_with_workout_plan():
    out = parse_plan("""```json
    {"summary": "Push/pull split with recovery focus.",
     "habits": [
       {"title": "Push day", "section": "exercise", "verify": "manual",
        "time": "18:00", "durationMins": 60, "cadence": "weekly", "days": [1, 4],
        "plan": {"name": "Push day", "type": "Weightlifting",
                 "sets": [{"name": "Bench", "w": 80, "r": 5},
                           {"name": "OHP", "w": 45, "r": 8},
                           {"name": "Junk", "w": -5, "r": 0}]}},
       {"title": "Protein", "section": "diet", "verify": "diet", "goalKey": "protein",
        "target": 150, "compare": "gte", "unit": "g", "cadence": "daily"},
       {"title": "In bed by", "section": "sleep", "verify": "metric",
        "metric": "sleep_schedule", "target": 23, "compare": "lte", "time": "22:30"}
     ]}
    ```""")
    assert "Push/pull" in out["summary"]
    push, protein, bed = out["habits"]
    # A planned workout forces workout-verification and keeps clean sets only.
    assert push["verify"] == "workout"
    assert push["days"] == [1, 4]
    assert [s["name"] for s in push["plan"]["sets"]] == ["Bench", "OHP", "Junk"]
    assert push["plan"]["sets"][0] == {"name": "Bench", "w": 80.0, "r": 5}
    assert "w" not in push["plan"]["sets"][2] and "r" not in push["plan"]["sets"][2]
    assert protein["target"] == 150.0 and protein["compare"] == "gte"
    assert bed["metric"] == "sleep_schedule" and bed["compare"] == "lte"


def test_parse_plan_sanitises_junk():
    out = parse_plan(
        '{"summary": 42, "habits": ['
        '{"title": "Ok", "section": "nope", "verify": "wat", "cadence": "weekly",'
        ' "days": [], "time": "25:99x", "durationMins": 9999},'
        '{"title": ""}, "not a dict",'
        '{"title": "Empty plan", "section": "exercise", "plan": {"sets": []}}]}')
    assert out["summary"] == "42"
    titles = [h["title"] for h in out["habits"]]
    assert titles == ["Ok", "Empty plan"]
    ok = out["habits"][0]
    assert ok["section"] == "misc" and ok["verify"] == "manual"
    assert ok["cadence"] == "daily"  # weekly with no days demoted
    assert "time" not in ok and "durationMins" not in ok
    assert "plan" not in out["habits"][1]  # empty plan dropped


def test_parse_plan_rejects_junk_entirely():
    assert parse_plan("sorry, no") is None
    assert parse_plan("") is None
    assert parse_plan('{"habits": []}') is None


def test_plan_endpoint_mocked(client, monkeypatch):
    from app.integrations.gemini import client as gem
    monkeypatch.setattr(gem, "configured", lambda: True)
    captured = {}

    def fake_generate(system, turns, **kw):
        captured["system"] = system
        captured["ask"] = turns[-1]["text"]
        return ('{"summary": "Focus recovery.", "habits": '
                '[{"title": "Meditate", "section": "recovery", "verify": "manual"}]}')

    monkeypatch.setattr(gem, "generate", fake_generate)
    r = client.post("/me/coach/plan", json={
        "message": "cut to 12% body fat",
        "habits": [{"title": "Train", "section": "exercise"}]})
    assert r.status_code == 200
    body = r.json()
    assert body["habits"][0]["title"] == "Meditate"
    # The model saw the roster-design rules, the user's context and their goal.
    assert "weekly habit roster" in captured["ask"] or "weekly plan" in captured["ask"]
    assert "cut to 12% body fat" in captured["ask"]
    assert "Train" in captured["system"]


def test_plan_endpoint_502_on_unparseable_reply(client, monkeypatch):
    from app.integrations.gemini import client as gem
    monkeypatch.setattr(gem, "configured", lambda: True)
    monkeypatch.setattr(gem, "generate", lambda *a, **k: "I cannot do that")
    r = client.post("/me/coach/plan", json={"message": ""})
    assert r.status_code == 502


def test_prompt_demands_grounding_and_json():
    assert "Never invent numbers" in PLAN_PROMPT
    assert "ONLY a JSON object" in PLAN_PROMPT
