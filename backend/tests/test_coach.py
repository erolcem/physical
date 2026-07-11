"""AI coach: PII-free context assembly, status, the chat endpoint (Gemini mocked),
and the unconfigured/auth guards."""
from app.coach import build_context, compose_system, parse_actions


def test_parse_actions_extracts_and_strips_valid_blocks():
    text = ('Add some mobility work.\n'
            '```action\n{"type": "add_habit", "title": "Mobility flow", '
            '"category": "exercise", "durationMins": 10, "time": "07:00"}\n```\n'
            'Keep it up!')
    clean, actions = parse_actions(text)
    assert "```" not in clean and "Add some mobility work." in clean and "Keep it up!" in clean
    assert actions == [{"type": "add_habit", "title": "Mobility flow",
                        "category": "exercise", "durationMins": 10, "time": "07:00"}]


def test_parse_actions_pin_correlation():
    _, actions = parse_actions(
        '```action\n{"type":"pin_correlation","a":"sleep_score","b":"bench"}\n```')
    assert actions == [{"type": "pin_correlation", "a": "sleep_score", "b": "bench"}]
    # a == b is dropped
    _, none = parse_actions('```action\n{"type":"pin_correlation","a":"x","b":"x"}\n```')
    assert none == []


def test_parse_actions_pin_note():
    _, actions = parse_actions(
        '```action\n{"type":"pin_note","text":"Cutting to 78 kg by September"}\n```')
    assert actions == [{"type": "pin_note", "text": "Cutting to 78 kg by September"}]
    # Empty text is dropped; long text is clipped to 120 chars.
    _, none = parse_actions('```action\n{"type":"pin_note","text":"  "}\n```')
    assert none == []
    _, clipped = parse_actions(
        '```action\n{"type":"pin_note","text":"' + 'x' * 200 + '"}\n```')
    assert len(clipped[0]["text"]) == 120


def test_parse_actions_sanitises_and_ignores_bad_blocks():
    # bad category → 'other', bad json → ignored, unknown type → ignored, no title → ignored.
    text = ('```action\n{"type":"add_habit","title":"X","category":"bogus"}\n```'
            '```action\n{not json}\n```'
            '```action\n{"type":"launch_rocket","title":"boom"}\n```'
            '```action\n{"type":"remove_habit","title":"Old"}\n```')
    _, actions = parse_actions(text)
    assert {"type": "add_habit", "title": "X", "category": "misc"} in actions
    assert {"type": "remove_habit", "title": "Old"} in actions
    assert len(actions) == 2  # the bad/unknown ones dropped


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


def test_context_includes_diet_training_aesthetics():
    ctx = build_context(
        [],
        diet={"calories": 2200, "protein": 150, "items": 4},
        training={"sessions": 3, "weekly_volume": 12000, "exercises": ["Bench", "Squat"]},
        aesthetics={"skin": 82, "oral": 90},
    )
    assert "2200 kcal" in ctx and "150g protein" in ctx
    assert "3 sessions" in ctx and "12000 volume" in ctx and "Bench" in ctx
    assert "skin 82" in ctx and "oral 90" in ctx


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

    def fake_generate_full(system, turns, **kw):
        captured["system"] = system
        captured["turns"] = turns
        return "Prioritise your weakest lift this week.", []

    monkeypatch.setattr(gem, "generate_full", fake_generate_full)

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


def test_coach_context_sections(client):
    client.post("/me/samples", json=[
        {"metric_id": "bench", "ts": "2026-06-01T08:00:00", "bodyweight_at_ts": 80,
         "value": 100, "source": "manual", "source_id": "b1"}])
    r = client.post("/me/coach/context", json={
        "habits": [{"title": "Train", "category": "strength", "streak": 4, "done_today": True}],
        "profile": {"age": 28, "gender": "male"}})
    assert r.status_code == 200
    body = r.json()
    assert body["profile"] == "age 28, male"
    assert body["overall"]  # has an overall rank from the bench log
    assert body["habits"] == ["Train [strength] · streak 4 · done today"]
    assert "never shared" in body["note"]


def test_coach_context_sections_show_meals_energy_history(client):
    # The transparency sheet must reflect EVERYTHING the coach is given —
    # meals, energy balance, and the raw-history footprint included.
    r = client.post("/me/coach/context", json={
        "meals": [{"d": "2026-07-05", "n": "Chicken bowl", "kcal": 650, "p": 45, "fib": 9}],
        "energy": {"in": [2100, 2300], "out": [2500, 2600], "bmr": 1800},
        "metric_history": {"sleep_score": [70, 75, 80], "steps": [9000, 11000]},
    })
    assert r.status_code == 200
    body = r.json()
    assert "Chicken bowl" in body["meals"] and "650" in body["meals"]
    assert "kcal in" in body["energy"] and "BMR ~1800" in body["energy"]
    assert "2 metrics" in body["history"]  # summarised footprint, not the raw dump
    assert "sleep_score" not in body["history"]
    # Absent extras stay null so the sheet simply skips those rows.
    r2 = client.post("/me/coach/context", json={})
    b2 = r2.json()
    assert b2["meals"] is None and b2["energy"] is None and b2["history"] is None
    assert b2["pins"] is None


def test_coach_context_shows_user_pins(client):
    r = client.post("/me/coach/context", json={
        "pins": ["Cutting to 78 kg by September", "Knee rehab — no deep squats"]})
    assert r.status_code == 200
    pins = r.json()["pins"]
    assert "Cutting to 78 kg by September" in pins and "no deep squats" in pins
    assert "Pinned by user" in pins  # framed as standing context


def test_coach_requires_auth():
    from fastapi.testclient import TestClient
    from app.main import app
    with TestClient(app) as c:
        assert c.post("/me/coach/chat", json={"message": "hi"}).status_code == 401


# ── Rich app-supplied context (ranks / correlations / sets / trends / habits) ──
from app.coach import build_context, parse_actions  # noqa: E402


def test_build_context_prefers_app_ranks_and_includes_analysis():
    ranks = {
        "overall": {"tier": "Gold", "sub": "II", "top_pct": 22},
        "categories": {"strength": {"tier": "Silver", "sub": "I", "top_pct": 40}},
        "metrics": [
            {"id": "bench", "label": "Bench", "tier": "Silver", "sub": "I", "top_pct": 40, "value": 90, "rank_value": 2.2, "trend": "up"},
            {"id": "vo2max", "label": "VO2max", "tier": "Gold", "sub": "III", "top_pct": 18, "value": 52, "rank_value": 3.7, "trend": "flat"},
        ],
    }
    corr = [{"a": "deep_sleep", "b": "bench", "r": 0.62, "n": 14}]
    trends = {"sleep_score": {"direction": "down", "change": -6, "recent": [82, 79, 74]}}
    sets = [{"date": "2026-06-27", "type": "strength",
             "exercises": [{"name": "Bench Press", "sets": [{"w": 80, "r": 8}, {"w": 80, "r": 7}]}]}]
    habits = [{"title": "Protein", "section": "diet", "target": 150, "unit": "g",
               "compare": "gte", "measured": 120, "met": False, "streak": 4, "adherence": 70}]
    ctx = build_context([], habits=habits, ranks=ranks, correlations=corr, trends=trends, workout_sets=sets)
    assert "Overall rank: Gold II" in ctx
    assert "deep_sleep ↔ bench: r=+0.62 (n=14)" in ctx
    assert "sleep_score" in ctx and "↓" in ctx          # trend arrow
    assert "Bench Press (80×8, 80×7)" in ctx             # individual sets
    assert "120≥150g" in ctx and "70% 30d" in ctx        # rich habit


def test_parse_adjust_habit_target_action():
    txt = ('Bump it up.\n```action\n{"type":"adjust_habit_target","title":"Protein",'
           '"target":170,"compare":"gte"}\n```')
    clean, actions = parse_actions(txt)
    assert "Bump it up." in clean and "```" not in clean
    assert actions == [{"type": "adjust_habit_target", "title": "Protein", "target": 170.0, "compare": "gte"}]


# ── Function-calling (tool use) ──
from app.coach import actions_from_calls, dedupe_actions, scrub_pii  # noqa: E402


def test_actions_from_function_calls():
    calls = [
        {"name": "add_habit", "args": {"title": "Mobility", "category": "exercise", "durationMins": 10}},
        {"name": "adjust_habit_target", "args": {"title": "Protein", "target": 170, "compare": "gte"}},
        {"name": "pin_correlation", "args": {"a": "deep_sleep", "b": "bench"}},
        {"name": "bogus", "args": {}},                      # invalid → dropped
        {"name": "add_habit", "args": {}},                  # no title → dropped
    ]
    acts = actions_from_calls(calls)
    assert {"type": "add_habit", "title": "Mobility", "category": "exercise", "durationMins": 10} in acts
    assert {"type": "adjust_habit_target", "title": "Protein", "target": 170.0, "compare": "gte"} in acts
    assert {"type": "pin_correlation", "a": "deep_sleep", "b": "bench"} in acts
    assert len(acts) == 3


def test_dedupe_merges_tool_and_fenced():
    a = [{"type": "add_habit", "title": "Mobility", "category": "misc"},
         {"type": "add_habit", "title": "Mobility", "category": "misc"}]
    assert len(dedupe_actions(a)) == 1


def test_scrub_pii_strips_email_and_long_ids_not_data():
    s = scrub_pii("contact a@b.com id 1234567890 but bench 80x8 sets stay")
    assert "a@b.com" not in s and "1234567890" not in s
    assert "80x8" in s  # set data preserved


def test_nudge_endpoint(client, monkeypatch):
    from app.integrations.gemini import client as gem
    monkeypatch.setattr(gem, "configured", lambda: True)
    monkeypatch.setattr(gem, "generate",
                        lambda system, turns, **kw: 'Readiness 78 — great day to push legs.')
    r = client.post("/me/coach/nudge", json={
        "message": "nudge",
        "habits": [{"title": "Train", "section": "exercise"}],
        "ranks": {"overall": {"tier": "Gold", "sub": "II", "top_pct": 20}},
    })
    assert r.status_code == 200
    assert r.json()["nudge"] == "Readiness 78 — great day to push legs."


def test_context_includes_meals_and_watch_rule():
    from app.coach import build_context
    from app.habit_check import VERIFY_PROMPT
    ctx = build_context([], meals=[
        {"d": "2026-07-01", "t": "08:10", "n": "Oats + whey", "kcal": 420, "p": 38, "fib": 6},
        {"d": "2026-07-01", "n": "Chicken rice", "kcal": 650, "p": 45},
    ])
    assert "Meals (last days" in ctx
    # Eaten-at time is real signal — the formatter must surface it, not drop it.
    assert "08:10 Oats + whey (420kcal, 38g P, 6g fib)" in ctx
    assert "Chicken rice (650kcal, 45g P)" in ctx  # time-less entries still fine
    # And the verifier knows typed sets need a tracked watch exercise.
    assert "WATCH ANCHORING" in VERIFY_PROMPT and "watch_verified" in VERIFY_PROMPT


# ── Habit memory rendering: every field the app computes must reach the model ──


def test_habit_lines_render_pattern_schedule_and_archived():
    from app.coach import build_context
    ctx = build_context([], habits=[
        {"title": "Protein", "section": "diet", "target": 150, "unit": "g",
         "compare": "gte", "measured": 120, "met": False, "streak": 4,
         "adherence": 70, "adherence_90d": 82, "recent_days": "––✓✓×✓✓✓×✓✓✓✓×",
         "cadence": "weekly", "days": [1, 3, 5], "time": "18:30",
         "created": "2026-05-01"},
        {"title": "Morning run", "section": "exercise", "archived": True,
         "created": "2026-01-10", "archived_on": "2026-06-01",
         "lifetime_due_days": 20, "lifetime_done_days": 15,
         "lifetime_adherence": 75},
    ])
    # Active habit: the 14-day pattern, both adherence scales, and the schedule.
    assert "last14 ––✓✓×✓✓✓×✓✓✓✓×" in ctx
    assert "70% 30d" in ctx and "82% 90d" in ctx
    assert "Mon Wed Fri" in ctx and "at 18:30" in ctx and "since 2026-05-01" in ctx
    # Archived habit: clearly retired, with its lifespan + lifetime adherence —
    # never rendered as if it were an active commitment.
    assert "🗄 Morning run" in ctx
    assert "RETIRED (2026-01-10 → 2026-06-01" in ctx
    assert "15/20 days" in ctx and "75% lifetime" in ctx
    # The done-today denominator counts ACTIVE habits only.
    assert "0/1 active done today" in ctx and "1 retired shown as history" in ctx


def test_context_sections_mark_archived_habits(client):
    r = client.post("/me/coach/context", json={
        "habits": [
            {"title": "Train", "section": "exercise", "streak": 4, "met": True},
            {"title": "Old run", "section": "exercise", "archived": True,
             "archived_on": "2026-06-01"},
        ]})
    assert r.status_code == 200
    habits = r.json()["habits"]
    assert "Train [exercise] · streak 4 · done today" in habits
    assert "🗄 Old run [exercise] · retired 2026-06-01" in habits


# ── History lookup tool (query_history): validation + replay turns ──
from app.coach import (MAX_QUERY_ROUNDS, QUERY_TOOLS, tool_event_turns,  # noqa: E402
                       validate_queries)


def test_validate_queries_accepts_clean_and_drops_malformed():
    good = {"name": "query_history",
            "args": {"topic": "metric", "id": "bench",
                     "start": "2026-03-01", "end": "2026-03-31"}}
    out = validate_queries([
        good,
        {"name": "query_history", "args": {"topic": "bogus", "start": "2026-03-01", "end": "2026-03-02"}},
        {"name": "query_history", "args": {"topic": "metric", "id": "hrv", "start": "March", "end": "2026-03-02"}},
        {"name": "query_history", "args": {"topic": "metric", "start": "2026-03-01", "end": "2026-03-02"}},  # no id
        {"name": "add_habit", "args": {"title": "X"}},  # not a query tool
    ])
    assert out == [{"name": "query_history",
                    "args": {"topic": "metric", "id": "bench",
                             "start": "2026-03-01", "end": "2026-03-31"}}]


def test_validate_queries_swaps_reversed_and_clamps_wide_ranges():
    out = validate_queries([
        {"name": "query_history", "args": {"topic": "meals",
                                           "start": "2026-03-31", "end": "2026-03-01"}},
        {"name": "query_history", "args": {"topic": "workouts",
                                           "start": "2020-01-01", "end": "2026-07-01"}},
    ])
    assert out[0]["args"]["start"] == "2026-03-01" and out[0]["args"]["end"] == "2026-03-31"
    # Six years collapses to the newest 366 days, keeping the requested end.
    assert out[1]["args"]["end"] == "2026-07-01" and out[1]["args"]["start"] == "2025-07-01"


def test_tool_event_turns_builds_paired_call_response_turns():
    events = [{
        "text": "Let me check March.",
        "calls": [{"name": "query_history",
                   "args": {"topic": "metric", "id": "bench",
                            "start": "2026-03-01", "end": "2026-03-31"}}],
        "results": [{"days": {"2026-03-02": 100.0}}],
    }]
    turns = tool_event_turns(events)
    assert len(turns) == 2
    model, user = turns
    assert model["role"] == "model" and model["text"] == "Let me check March."
    assert model["fn_calls"][0]["args"]["id"] == "bench"
    assert user["role"] == "user"
    assert user["fn_responses"] == [{"name": "query_history",
                                     "response": {"days": {"2026-03-02": 100.0}}}]
    # A missing/malformed result still pairs the call with a readable error.
    broken = tool_event_turns([{"calls": events[0]["calls"], "results": []}])
    assert broken[1]["fn_responses"][0]["response"] == {"error": "no result returned"}
    # Events whose calls are all invalid are skipped entirely.
    assert tool_event_turns([{"calls": [{"name": "nope"}], "results": []}]) == []
    # Results get the same PII scrub as the main context — free-text habit
    # titles / food names must not become a scrub bypass.
    leaky = tool_event_turns([{"calls": events[0]["calls"],
                               "results": [{"note": "email a@b.com id 12345678901"}]}])
    resp = leaky[1]["fn_responses"][0]["response"]["note"]
    assert "a@b.com" not in resp and "12345678901" not in resp


def test_gemini_turn_parts_encode_function_calls_and_responses():
    from app.integrations.gemini.client import _turn_parts
    # Plain text turns are unchanged (back-compat with every other caller).
    assert _turn_parts({"text": "hi"}) == [{"text": "hi"}]
    model = _turn_parts({"text": "Checking…", "fn_calls": [
        {"name": "query_history", "args": {"topic": "meals"}}]})
    assert model == [{"text": "Checking…"},
                     {"functionCall": {"name": "query_history",
                                       "args": {"topic": "meals"}}}]
    # A call-only model turn carries no empty text part.
    only_call = _turn_parts({"text": "", "fn_calls": [{"name": "query_history", "args": {}}]})
    assert only_call == [{"functionCall": {"name": "query_history", "args": {}}}]
    user = _turn_parts({"fn_responses": [{"name": "query_history",
                                          "response": {"days": {}}}]})
    assert user == [{"functionResponse": {"name": "query_history",
                                          "response": {"days": {}}}}]


def test_coach_chat_returns_pending_queries_then_final_answer(client, monkeypatch):
    from app.integrations.gemini import client as gem
    monkeypatch.setattr(gem, "configured", lambda: True)
    captured = {}

    def fake_generate_full(system, turns, tools=None, **kw):
        captured["turns"] = turns
        captured["tools"] = tools
        # No resolved lookups yet → the model asks for March bench history.
        if not any("fn_responses" in t for t in turns):
            return "", [{"name": "query_history",
                         "args": {"topic": "metric", "id": "bench",
                                  "start": "2026-03-01", "end": "2026-03-31"}}]
        return "March bench averaged 100kg — flat month.", []

    monkeypatch.setattr(gem, "generate_full", fake_generate_full)

    # Round 1: the app gets the pending query back (no actions yet).
    r1 = client.post("/me/coach/chat", json={"message": "How was my bench in March?"})
    assert r1.status_code == 200
    body = r1.json()
    assert body["queries"] == [{"name": "query_history",
                                "args": {"topic": "metric", "id": "bench",
                                         "start": "2026-03-01", "end": "2026-03-31"}}]
    assert body["actions"] == []
    assert any(t["name"] == "query_history" for t in captured["tools"])

    # Round 2: the app resolved it locally and re-posts with the tool event.
    r2 = client.post("/me/coach/chat", json={
        "message": "How was my bench in March?",
        "tool_events": [{"text": "", "calls": body["queries"],
                         "results": [{"days": {"2026-03-02": 100.0}}]}]})
    assert r2.status_code == 200
    assert r2.json()["reply"] == "March bench averaged 100kg — flat month."
    assert r2.json()["queries"] == []
    # The replay reached Gemini as paired functionCall / functionResponse turns.
    roles = [(t["role"], "fn_calls" in t, "fn_responses" in t) for t in captured["turns"]]
    assert ("model", True, False) in roles and ("user", False, True) in roles


def test_coach_chat_withholds_query_tool_at_round_cap(client, monkeypatch):
    from app.integrations.gemini import client as gem
    monkeypatch.setattr(gem, "configured", lambda: True)
    captured = {}

    def fake_generate_full(system, turns, tools=None, **kw):
        captured["tools"] = tools
        return "Final answer.", []

    monkeypatch.setattr(gem, "generate_full", fake_generate_full)
    ev = {"text": "", "calls": [{"name": "query_history",
                                 "args": {"topic": "meals", "start": "2026-06-01",
                                          "end": "2026-06-07"}}],
          "results": [{"days": {}}]}
    r = client.post("/me/coach/chat", json={
        "message": "hi", "tool_events": [ev] * MAX_QUERY_ROUNDS})
    assert r.status_code == 200 and r.json()["reply"] == "Final answer."
    # At the cap the model gets NO query tool — it must answer in text.
    assert not any(t["name"] == "query_history" for t in captured["tools"])
    assert QUERY_TOOLS[0]["name"] == "query_history"  # declaration intact
