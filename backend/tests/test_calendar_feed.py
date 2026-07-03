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
    # Anchored on the next due weekday (Mon), not the Sunday "now" — otherwise
    # Google renders a stray off-schedule first instance.
    assert timed["start"]["dateTime"] == "2026-06-29T07:30:00"
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


def test_calendar_push_flags_disabled_api(client, monkeypatch):
    """SERVICE_DISABLED from Google (Calendar API off in the Cloud console) must
    surface as a distinct 412, not a generic 'reconnect' the user can't fix."""
    import datetime as dt
    import httpx
    from app.db import get_db
    from app.main import app as _app
    from app.models import GoogleCalendarToken
    gen = _app.dependency_overrides[get_db]()
    db = next(gen)
    db.merge(GoogleCalendarToken(
        user_id="local-dev", access_token="a", refresh_token="r",
        expires_at=dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=1),
        scope="https://www.googleapis.com/auth/calendar.events"))
    db.commit()

    def fake_get(url, **kw):
        return httpx.Response(
            403, text='{"error": {"status": "PERMISSION_DENIED", "details": '
                      '[{"reason": "SERVICE_DISABLED"}]}}',
            request=httpx.Request("GET", url))

    monkeypatch.setattr(httpx, "get", fake_get)
    r = client.post("/me/calendar/push", json={"habits": [{"id": "h", "title": "T"}]})
    assert r.status_code == 412
    assert "calendar_api_disabled" in r.json()["detail"]


def _seed_calendar_token(monkeypatch=None):
    import datetime as dt
    from app.db import get_db
    from app.main import app as _app
    from app.models import GoogleCalendarToken
    gen = _app.dependency_overrides[get_db]()
    db = next(gen)
    db.merge(GoogleCalendarToken(
        user_id="local-dev", access_token="a", refresh_token="r",
        expires_at=dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=1),
        scope="https://www.googleapis.com/auth/calendar.events"))
    db.commit()


def test_event_id_is_deterministic_and_calendar_safe():
    from app.routers.calendar import habit_event_id
    a, b = habit_event_id("h1"), habit_event_id("h1")
    assert a == b and a != habit_event_id("h2")
    # Google event ids must use the base32hex charset [0-9a-v] — sha1 hex fits.
    assert all(c in "0123456789abcdefghijklmnopqrstuv" for c in a)
    assert 5 <= len(a) <= 1024


def test_calendar_push_reconciles_duplicates_and_removed(client, monkeypatch):
    """Racy pushes tripled the calendar; the reconcile keeps ONE deterministic
    event per habit, deletes the strays, and prunes habits that no longer exist."""
    import httpx
    from app.routers.calendar import habit_event_id
    _seed_calendar_token()
    canonical = habit_event_id("h1")
    deleted, puts, posts = [], [], []

    def fake_get(url, **kw):
        return httpx.Response(200, json={"items": [
            {"id": canonical, "extendedProperties": {"private": {"habit": "h1"}}},
            {"id": "legacyA", "extendedProperties": {"private": {"habit": "h1"}}},
            {"id": "legacyB", "extendedProperties": {"private": {"habit": "h1"}}},
            {"id": "legacyC", "extendedProperties": {"private": {"habit": "gone"}}},
        ]}, request=httpx.Request("GET", url))

    def fake_put(url, json=None, **kw):
        puts.append((url, json))
        return httpx.Response(200, json={}, request=httpx.Request("PUT", url))

    def fake_post(url, json=None, **kw):
        posts.append((url, json))
        return httpx.Response(200, json={}, request=httpx.Request("POST", url))

    def fake_delete(url, **kw):
        deleted.append(url.rsplit("/", 1)[-1])
        return httpx.Response(204, request=httpx.Request("DELETE", url))

    monkeypatch.setattr(httpx, "get", fake_get)
    monkeypatch.setattr(httpx, "put", fake_put)
    monkeypatch.setattr(httpx, "post", fake_post)
    monkeypatch.setattr(httpx, "delete", fake_delete)

    r = client.post("/me/calendar/push", json={
        "habits": [{"id": "h1", "title": "Train", "time": "18:00", "dur": 60}],
        "tz": "Australia/Sydney"})
    assert r.status_code == 200
    body = r.json()
    assert body == {"added": 0, "updated": 1, "removed": 1, "deduped": 2, "failed": 0}
    # The canonical slot was updated in place with the fixed id + confirmed status…
    assert puts and puts[0][0].endswith(canonical)
    assert puts[0][1]["id"] == canonical and puts[0][1]["status"] == "confirmed"
    assert not posts
    # …and every stray copy + the orphaned habit's event were deleted.
    assert sorted(deleted) == ["legacyA", "legacyB", "legacyC"]


def test_calendar_push_insert_conflict_falls_back_to_update(client, monkeypatch):
    """A concurrent push (or a previously-deleted 'cancelled' slot) makes the
    fixed-id insert 409 — the push must update/resurrect instead of failing."""
    import httpx
    from app.routers.calendar import habit_event_id
    _seed_calendar_token()
    calls = []

    def fake_get(url, **kw):
        return httpx.Response(200, json={"items": []}, request=httpx.Request("GET", url))

    def fake_post(url, json=None, **kw):
        calls.append("post")
        return httpx.Response(409, text="duplicate id", request=httpx.Request("POST", url))

    def fake_put(url, json=None, **kw):
        calls.append("put")
        assert url.endswith(habit_event_id("h1"))
        return httpx.Response(200, json={}, request=httpx.Request("PUT", url))

    monkeypatch.setattr(httpx, "get", fake_get)
    monkeypatch.setattr(httpx, "post", fake_post)
    monkeypatch.setattr(httpx, "put", fake_put)
    monkeypatch.setattr(httpx, "delete",
                        lambda url, **kw: httpx.Response(204, request=httpx.Request("DELETE", url)))

    r = client.post("/me/calendar/push", json={"habits": [{"id": "h1", "title": "Train"}]})
    assert r.status_code == 200
    assert r.json()["updated"] == 1 and r.json()["failed"] == 0
    assert calls == ["post", "put"]


def test_recurring_events_anchor_on_a_matching_weekday():
    """A weekly Mon/Thu habit anchored on a Wednesday renders a stray
    off-schedule first instance — the anchor must move to the next due day."""
    import datetime as dt
    from app.calendar_feed import build_ics, habit_event
    wednesday = dt.datetime(2026, 7, 1, 9, 0)  # 2026-07-01 is a Wednesday
    h = {"id": "h", "title": "Push day", "time": "18:00", "dur": 60,
         "cadence": "weekly", "days": [1, 4]}  # Mon + Thu
    ev = habit_event(h, tz="Australia/Sydney", now=wednesday)
    assert ev["start"]["dateTime"].startswith("2026-07-02")  # Thursday
    assert "BYDAY=MO,TH" in ev["recurrence"][0]
    # Daily habits stay anchored on today.
    ev2 = habit_event({"id": "d", "title": "Read", "time": "21:00"}, now=wednesday)
    assert ev2["start"]["dateTime"].startswith("2026-07-01")
    # The ICS feed anchors the same way.
    ics = build_ics([h], now=wednesday)
    assert "DTSTART:20260702T180000" in ics
