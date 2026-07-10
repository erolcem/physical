"""LLM habit verification: prompt payload building, defensive verdict parsing, and
the /me/habits/verify endpoint (Gemini mocked)."""
import json

from app.habit_check import VERIFY_PROMPT, build_evidence, parse_verdicts


def test_build_evidence_carries_everything():
    payload = build_evidence(
        "2026-07-01",
        habits=[{"id": "h1", "title": "Train", "section": "exercise"}],
        workouts=[{"type": "Weightlifting", "sets": [{"name": "Bench", "w": 80, "r": 5}]}],
        food=[{"name": "Oats", "calories": 350}],
        metrics={"steps": 9000, "sleep_score": 82},
    )
    obj = json.loads(payload)
    assert obj["date"] == "2026-07-01"
    assert obj["habits"][0]["id"] == "h1"
    assert obj["evidence"]["workout_sessions"][0]["sets"][0]["name"] == "Bench"
    assert obj["evidence"]["metric_readings"]["steps"] == 9000


def test_prompt_encodes_the_exclusivity_and_strictness_rules():
    assert "EVIDENCE EXCLUSIVITY" in VERIFY_PROMPT
    assert "TARGETS ARE BINDING" in VERIFY_PROMPT
    assert "NOT DONE" in VERIFY_PROMPT
    # The description is binding and matching is specific (the makiwara-vs-walk fix).
    assert "HONOUR THE DESCRIPTION" in VERIFY_PROMPT
    assert "Makiwara" in VERIFY_PROMPT
    assert "TIME-OF-DAY" in VERIFY_PROMPT
    # Meal identity: a breakfast entry can never tick a Dinner habit — food
    # entries carry an eaten-at time the verifier must match to the meal window.
    assert "MEAL IDENTITY" in VERIFY_PROMPT
    assert "breakfast entry NEVER satisfies a dinner habit" in VERIFY_PROMPT
    assert "WATCH ANCHORING" in VERIFY_PROMPT


def test_build_evidence_carries_food_times():
    payload = build_evidence(
        "2026-07-01",
        habits=[{"id": "d1", "title": "Dinner", "section": "diet", "verify": "diet"}],
        workouts=[],
        food=[{"name": "Eggs", "time": "07:40", "calories": 420},
              {"name": "Chicken and rice", "time": "19:10", "meal_type": "DINNER",
               "calories": 700}],
        metrics={})
    obj = json.loads(payload)
    foods = obj["evidence"]["food_log"]
    assert foods[0]["time"] == "07:40"
    assert foods[1]["meal_type"] == "DINNER"


def test_build_evidence_carries_the_habit_description():
    payload = build_evidence(
        "2026-07-01",
        habits=[{"id": "h1", "title": "Cardio", "section": "exercise",
                 "description": "Evening makiwara punching, 20+ min"}],
        workouts=[], food=[], metrics={})
    assert "makiwara" in payload


def test_parse_verdicts_happy_path():
    out = parse_verdicts(
        '{"verdicts": [{"id": "a", "done": true, "reason": "lifting session logged"},'
        ' {"id": "b", "done": false, "reason": "no cardio evidence"}]}',
        ["a", "b"])
    assert out == [
        {"id": "a", "done": True, "reason": "lifting session logged"},
        {"id": "b", "done": False, "reason": "no cardio evidence"},
    ]


def test_parse_verdicts_defaults_missing_to_not_done_and_drops_unknown():
    out = parse_verdicts(
        'Sure! ```json\n{"verdicts": [{"id": "a", "done": true, "reason": "ok"},'
        ' {"id": "zzz", "done": true}]}\n```',
        ["a", "b"])
    assert out[0] == {"id": "a", "done": True, "reason": "ok"}
    assert out[1]["id"] == "b" and out[1]["done"] is False  # missing → not done


def test_parse_verdicts_never_raises_on_junk():
    assert [v["done"] for v in parse_verdicts("not json at all", ["a"])] == [False]
    assert [v["done"] for v in parse_verdicts("", ["a"])] == [False]
    # a truthy string is NOT true — booleans only
    out = parse_verdicts('{"verdicts": [{"id": "a", "done": "yes"}]}', ["a"])
    assert out[0]["done"] is False


def test_verify_endpoint_mocked(client, monkeypatch):
    from app.integrations.gemini import client as gem
    monkeypatch.setattr(gem, "configured", lambda: True)
    captured = {}

    def fake_generate(system, turns, **kw):
        captured["system"] = system
        captured["payload"] = turns[-1]["text"]
        captured["model"] = kw.get("model")
        return ('{"verdicts": [{"id": "t1", "done": true, "reason": "weights session"},'
                ' {"id": "t2", "done": false, "reason": "same session cannot count twice"}]}')

    monkeypatch.setattr(gem, "generate", fake_generate)
    r = client.post("/me/habits/verify", json={
        "day": "2026-07-01",
        "habits": [
            {"id": "t1", "title": "Train", "section": "exercise"},
            {"id": "t2", "title": "Cardio session", "section": "exercise"},
        ],
        "workouts": [{"type": "Weightlifting",
                      "sets": [{"name": "Bench", "w": 80, "r": 5}]}],
        "food": [],
        "metrics": {"steps": 4000},
    })
    assert r.status_code == 200
    verdicts = r.json()["verdicts"]
    assert verdicts[0] == {"id": "t1", "done": True, "reason": "weights session"}
    assert verdicts[1]["done"] is False
    # The model saw the strict rules and the evidence.
    assert "EVIDENCE EXCLUSIVITY" in captured["system"]
    assert "Bench" in captured["payload"]
    # Verification runs on the PRO model (correctness-critical, low-frequency).
    from app.config import settings
    assert captured["model"] == settings.gemini_model
    assert r.json()["model"] == settings.gemini_model


def test_verify_endpoint_503_when_unconfigured(client):
    r = client.post("/me/habits/verify", json={"day": "2026-07-01",
                                               "habits": [{"id": "x", "title": "T"}]})
    assert r.status_code == 503
