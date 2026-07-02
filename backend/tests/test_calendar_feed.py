import datetime as dt
from app.calendar_feed import build_ics, feed_token, verify_token


def test_token_round_trip():
    uid = "google-oauth2|12345"
    tok = feed_token(uid)
    assert verify_token(tok) == uid
    assert verify_token(tok + "x") is None
    assert verify_token("garbage") is None


def test_build_ics_timed_and_untimed():
    now = dt.datetime(2026, 6, 28, 9, 0, 0)
    habits = [
        {"id": "h1", "title": "Sleep score", "cat": "sleep", "time": "23:00",
         "dur": 0, "cadence": "daily", "target": 80, "unit": "/100"},
        {"id": "h2", "title": "Train", "cat": "exercise", "time": "07:30",
         "dur": 60, "cadence": "weekly", "days": [1, 3, 5]},
        {"id": "h3", "title": "Skincare", "cat": "aesthetics", "cadence": "daily"},  # untimed
    ]
    ics = build_ics(habits, now=now)
    assert ics.startswith("BEGIN:VCALENDAR")
    assert ics.strip().endswith("END:VCALENDAR")
    assert ics.count("BEGIN:VEVENT") == 3
    assert "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR" in ics
    assert "DTSTART:20260628T230000" in ics          # timed habit
    assert "DTSTART;VALUE=DATE:20260628" in ics       # untimed → all-day
    assert "SUMMARY:Sleep score" in ics
    assert "target ≥ 80/100" in ics


def test_habit_event_timed_and_untimed():
    from app.calendar_feed import habit_event
    import datetime as dt
    now = dt.datetime(2026, 6, 28, 9, 0, 0)
    timed = habit_event({"id": "h1", "title": "Train", "cat": "exercise", "time": "07:30",
                         "dur": 60, "cadence": "weekly", "days": [1, 3, 5], "target": 12,
                         "unit": "sets", "cmp": "gte"}, tz="Europe/London", now=now)
    assert timed["summary"] == "Train"
    assert timed["start"]["dateTime"] == "2026-06-28T07:30:00"
    assert timed["start"]["timeZone"] == "Europe/London"
    assert timed["recurrence"] == ["RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR"]
    assert timed["extendedProperties"]["private"] == {"app": "physical", "habit": "h1"}
    untimed = habit_event({"id": "h2", "title": "Skincare", "cadence": "daily"}, now=now)
    assert "date" in untimed["start"]
    assert untimed["recurrence"] == ["RRULE:FREQ=DAILY"]


def test_habit_event_timed_always_has_a_timezone():
    # The Calendar API rejects RECURRING events whose dateTime has no timeZone —
    # a missing app tz must fall back to UTC, not to a floating (rejected) time.
    from app.calendar_feed import habit_event
    ev = habit_event({"id": "h", "title": "Train", "time": "18:00", "dur": 60})
    assert ev["start"]["timeZone"] == "UTC"
    ev2 = habit_event({"id": "h", "title": "Train", "time": "18:00"},
                      tz="Australia/Sydney")
    assert ev2["start"]["timeZone"] == "Australia/Sydney"
    # All-day (untimed) events don't need one.
    ev3 = habit_event({"id": "h", "title": "Read"})
    assert "timeZone" not in ev3["start"] and "date" in ev3["start"]
