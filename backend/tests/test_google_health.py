"""Google Health adapter: OAuth URL construction, dataPoint→canonical mapping,
and router wiring. The live pull is verified once a Google account is connected."""
from app.integrations.google_health import mapping, oauth


def test_authorize_url_uses_google_and_requests_offline_health_scopes():
    url = oauth.authorize_url("user-123")
    assert url.startswith("https://accounts.google.com/o/oauth2/v2/auth")
    assert "googlehealth.health_metrics_and_measurements.readonly" in url
    assert "googlehealth.sleep.readonly" in url
    assert "access_type=offline" in url and "prompt=consent" in url
    assert "state=user-123" in url
    # Calendar must NEVER ride on the health consent: health.googleapis.com
    # rejects tokens carrying calendar.events (403 DISALLOWED_OAUTH_SCOPES).
    assert "calendar" not in url
    # And incremental auth must be OFF, or Google would re-bundle a previously
    # granted calendar scope back onto the fresh health token.
    assert "include_granted_scopes" not in url


def test_calendar_authorize_url_is_calendar_only():
    url = oauth.authorize_url("user-123", scopes=oauth.CALENDAR_SCOPES)
    assert "calendar.events" in url
    assert "googlehealth" not in url


def test_resting_hr_real_google_shape():
    pts = [{
        "dataSource": {"platform": "FITBIT", "device": {"displayName": "Inspire 3"}},
        "dailyRestingHeartRate": {
            "date": {"year": 2026, "month": 6, "day": 23},
            "beatsPerMinute": "49",
            "dailyRestingHeartRateMetadata": {"calculationMethod": "WITH_SLEEP"},
        },
    }]
    out = mapping.to_samples("resting_hr", pts)
    assert out[0]["value"] == 49.0 and out[0]["ts"] == "2026-06-23T00:00:00"


def test_hrv_prefers_deep_sleep_rmssd_over_zero_average():
    pts = [{"dataSource": {}, "dailyHeartRateVariability": {
        "date": {"year": 2026, "month": 6, "day": 24},
        "averageHeartRateVariabilityMilliseconds": 0,
        "deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds": 122.05}}]
    assert mapping.to_samples("hrv", pts)[0]["value"] == 122.05


def test_vo2max_uses_vo2Max_field():
    pts = [{"dataSource": {}, "dailyVo2Max": {
        "date": {"year": 2026, "month": 6, "day": 24},
        "vo2Max": 54.28, "vo2MaxCovariance": 6.03}}]
    assert mapping.to_samples("vo2max", pts)[0]["value"] == 54.28


def test_bodyweight_nested_date_and_grams_to_kg():
    pts = [{"name": "users/x/weight/y", "dataSource": {}, "weight": {
        "sampleTime": {"civilTime": {"date": {"year": 2026, "month": 4, "day": 30}}},
        "weightGrams": 82000}}]
    out = mapping.to_samples("bodyweight", pts)
    assert out[0]["value"] == 82.0 and out[0]["ts"] == "2026-04-30T00:00:00"


def test_sleep_score_rhr_restoration_personalised():
    night = [{"dataSource": {}, "sleep": {
        "interval": {"startTime": "2026-06-25T16:00:00Z"},
        "summary": {"minutesInSleepPeriod": "480", "minutesAsleep": "450",
                    "stagesSummary": [{"type": "DEEP", "minutes": "90"},
                                      {"type": "REM", "minutes": "90"}]}}}]
    # A resting HR well below the user's baseline → strong restoration → higher score
    # than the same night with a resting HR above baseline.
    good = mapping.to_samples("sleep", night, rhr_by_day={"2026-06-25": 48}, baseline_rhr=58)
    bad = mapping.to_samples("sleep", night, rhr_by_day={"2026-06-25": 68}, baseline_rhr=58)
    gscore = next(s["value"] for s in good if s["metric_id"] == "sleep_score")
    bscore = next(s["value"] for s in bad if s["metric_id"] == "sleep_score")
    assert gscore > bscore


def test_parse_intraday_daily_sums_per_day():
    pts = [
        {"steps": {"interval": {"civilStartTime": {"date": {"year": 2026, "month": 6, "day": 26}}}, "count": "6"}},
        {"steps": {"interval": {"civilStartTime": {"date": {"year": 2026, "month": 6, "day": 26}}}, "count": "10"}},
        {"steps": {"interval": {"civilStartTime": {"date": {"year": 2026, "month": 6, "day": 25}}}, "count": "4"}},
    ]
    out = {s["ts"][:10]: s["value"] for s in mapping.parse_intraday_daily("steps", pts, "steps", "count")}
    assert out["2026-06-26"] == 16.0 and out["2026-06-25"] == 4.0


def test_parse_exercise_sessions_real_shape():
    pts = [{
        "name": "users/x/dataTypes/exercise/dataPoints/5044284279678279720",
        "dataSource": {"platform": "FITBIT"},
        "exercise": {
            "interval": {"startTime": "2026-06-23T03:43:41Z", "startUtcOffset": "36000s",
                         "endTime": "2026-06-23T04:21:01Z", "endUtcOffset": "36000s"},
            "exerciseType": "WALKING",
            "metricsSummary": {
                "caloriesKcal": 229, "distanceMillimeters": 1635492, "steps": "2148",
                "averageHeartRateBeatsPerMinute": "73",
                "heartRateZoneDurations": {"lightTime": "2280s", "moderateTime": "120s",
                                           "vigorousTime": "0s", "peakTime": "0s"},
            },
            "displayName": "Walk", "activeDuration": "2240s",
        },
    }]
    s = mapping.parse_exercise_sessions(pts)[0]
    assert s["google_id"] == "5044284279678279720"
    assert s["type"] == "Walk" and s["exercise_type"] == "WALKING"
    assert s["start"] == "2026-06-23T13:43:41"  # +10h local
    assert s["duration_mins"] == 37  # 2240s
    assert s["calories"] == 229.0
    assert s["distance_km"] == 1.64  # 1635492 mm
    assert s["steps"] == 2148.0 and s["avg_hr"] == 73.0
    assert s["zone_minutes"] == 2  # 120s moderate
    assert s["cardio_load"] == 42  # Edwards TRIMP: 38min light×1 + 2min moderate×2


def test_intraday_heart_rate_averages_per_day():
    pts = [
        {"heartRate": {"sampleTime": {"physicalTime": "2026-06-26T12:00:00Z"}, "beatsPerMinute": "60"}},
        {"heartRate": {"sampleTime": {"physicalTime": "2026-06-26T18:00:00Z"}, "beatsPerMinute": "80"}},
        {"heartRate": {"sampleTime": {"physicalTime": "2026-06-25T10:00:00Z"}, "beatsPerMinute": "50"}},
    ]
    out = {s["ts"][:10]: s["value"]
           for s in mapping.parse_intraday_daily("heart_rate", pts, "heartRate", "beatsPerMinute", agg="avg")}
    assert out["2026-06-26"] == 70.0  # (60+80)/2
    assert out["2026-06-25"] == 50.0


def test_intraday_steps_sum_per_day():
    pts = [
        {"steps": {"interval": {"civilStartTime": {"date": {"year": 2026, "month": 6, "day": 26}}}, "count": "6"}},
        {"steps": {"interval": {"civilStartTime": {"date": {"year": 2026, "month": 6, "day": 26}}}, "count": "10"}},
    ]
    out = mapping.parse_intraday_daily("steps", pts, "steps", "count")
    assert out[0]["value"] == 16.0 and out[0]["ts"] == "2026-06-26T00:00:00"


def test_height_real_shape_mm_to_cm():
    pts = [{"name": "x", "dataSource": {}, "height": {
        "sampleTime": {"civilTime": {"date": {"year": 2026, "month": 4, "day": 30}}},
        "heightMillimeters": "1900"}}]
    out = mapping.to_samples("height", pts)
    assert out[0]["value"] == 190.0 and out[0]["ts"] == "2026-04-30T00:00:00"


def test_sleep_expands_to_duration_efficiency_and_stages():
    pts = [{"name": "x", "dataSource": {}, "sleep": {
        "interval": {"startTime": "2026-06-23T13:56:00Z", "endTime": "2026-06-23T23:41:00Z"},
        "summary": {"minutesInSleepPeriod": "585", "minutesAsleep": "554",
                    "stagesSummary": [{"type": "DEEP", "minutes": "101"},
                                      {"type": "REM", "minutes": "126"},
                                      {"type": "LIGHT", "minutes": "326"}]}}}]
    out = {s["metric_id"]: s for s in mapping.to_samples("sleep", pts)}
    assert round(out["sleep_duration"]["value"], 2) == round(554 / 60, 2)
    assert out["sleep_efficiency"]["value"] == 94.7   # 554/585*100
    assert out["deep_sleep"]["value"] == 101.0
    assert out["rem_sleep"]["value"] == 126.0
    assert all(s["ts"] == "2026-06-23T00:00:00" for s in out.values())


def test_sleep_real_shape_local_day_and_subfields():
    # The exact /debug shape: +10h offset, schedule, interruptions vs full awakenings.
    pts = [{"name": "x", "dataSource": {}, "sleep": {
        "interval": {"startTime": "2026-06-24T15:54:00Z", "startUtcOffset": "36000s",
                     "endTime": "2026-06-24T21:58:00Z", "endUtcOffset": "36000s"},
        "stages": [
            {"type": "AWAKE", "startTime": "2026-06-24T16:00:00Z", "endTime": "2026-06-24T16:07:00Z"},  # 7m → full
            {"type": "DEEP", "startTime": "2026-06-24T16:07:00Z", "endTime": "2026-06-24T17:00:00Z"},
            {"type": "AWAKE", "startTime": "2026-06-24T20:00:00Z", "endTime": "2026-06-24T20:02:00Z"},  # 2m → micro
        ],
        "summary": {"minutesInSleepPeriod": "364", "minutesAsleep": "349",
                    "minutesToFallAsleep": "0",
                    "stagesSummary": [{"type": "AWAKE", "minutes": "14", "count": "2"},
                                      {"type": "DEEP", "minutes": "73", "count": "5"},
                                      {"type": "REM", "minutes": "80", "count": "5"}]}}}]
    out = {s["metric_id"]: s for s in mapping.to_samples("sleep", pts)}
    # +10h offset moves the UTC start (24th) to the LOCAL 25th.
    assert all(s["ts"] == "2026-06-25T00:00:00" for s in out.values())
    assert out["time_to_sleep"]["value"] == 0.0
    assert out["sleep_interruptions"]["value"] == 2.0  # every AWAKE event
    assert out["full_awakenings"]["value"] == 1.0      # only the ≥5-min AWAKE block
    assert out["sleep_schedule"]["value"] == 1.9       # 01:54 local bedtime
    assert out["deep_sleep"]["value"] == 73.0 and out["rem_sleep"]["value"] == 80.0
    assert out["sleep_efficiency"]["value"] == 95.9  # 349/364×100


def test_sleep_score_derived_lands_near_population_mean():
    # 7h asleep, 87.5% efficiency, ~29% deep+REM → a middling night ≈ engine mean (77).
    pts = [{"dataSource": {}, "sleep": {
        "interval": {"startTime": "2026-06-25T13:00:00Z"},
        "summary": {"minutesInSleepPeriod": "480", "minutesAsleep": "420",
                    "stagesSummary": [{"type": "DEEP", "minutes": "60"},
                                      {"type": "REM", "minutes": "60"}]}}}]
    out = {s["metric_id"]: s for s in mapping.to_samples("sleep", pts)}
    assert out["sleep_score"]["value"] == 77.2
    assert out["sleep_score"]["ts"] == "2026-06-25T00:00:00"


def test_sleep_score_prefers_vendor_score_when_present():
    pts = [{"dataSource": {}, "sleep": {
        "interval": {"startTime": "2026-06-25T13:00:00Z"},
        "summary": {"minutesAsleep": "420", "minutesInSleepPeriod": "480",
                    "overallScore": 88}}}]  # vendor's own 0–100 score wins over the derived one
    out = {s["metric_id"]: s for s in mapping.to_samples("sleep", pts)}
    assert out["sleep_score"]["value"] == 88.0


def test_background_steps_active_zone_energy_extractors():
    steps = mapping.to_samples("steps", [{"dataSource": {}, "dailySteps": {
        "date": {"year": 2026, "month": 6, "day": 24}, "count": "8000"}}])
    assert steps[0]["value"] == 8000.0 and steps[0]["ts"] == "2026-06-24T00:00:00"

    azm = mapping.to_samples("active_zone", [{"dataSource": {}, "dailyActiveZoneMinutes": {
        "date": {"year": 2026, "month": 6, "day": 24}, "minutes": 45}}])
    assert azm[0]["value"] == 45.0

    energy = mapping.to_samples("energy_burned", [{"dataSource": {}, "dailyActiveCaloriesBurned": {
        "date": {"year": 2026, "month": 6, "day": 24}, "energyKcal": 520}}])
    assert energy[0]["value"] == 520.0


def test_valueless_points_are_skipped():
    assert mapping.to_samples("vo2max", []) == []
    assert mapping.to_samples("hrv", [{"dataSource": {}, "dailyHeartRateVariability": {
        "date": {"year": 2026, "month": 6, "day": 20}}}]) == []  # no rmssd field


def test_sync_requires_a_connection(client):
    r = client.post("/integrations/google/sync")  # signed-in user, no Google link
    assert r.status_code == 404


def test_authorize_needs_client_id(client):
    r = client.get("/integrations/google/authorize")  # signed in, but no client id
    assert r.status_code == 500


def test_endpoints_require_auth():
    from fastapi.testclient import TestClient
    from app.main import app
    with TestClient(app) as c:  # no Authorization header
        assert c.get("/me/ranks").status_code == 401
        assert c.post("/integrations/google/sync").status_code == 401


def test_status_reports_not_connected(client):
    r = client.get("/integrations/google/status")
    assert r.status_code == 200 and r.json()["connected"] is False


def test_parse_nutrition_log_real_shape():
    # The exact /debug nutrition-log shape (chicken thigh): +10h offset → local day,
    # reliable energy + macros; protein/fibre come from the nutrients array.
    pts = [{"name": "users/x/dataTypes/nutrition-log/dataPoints/7534057579911318776",
            "nutritionLog": {
                "interval": {"startTime": "2026-06-27T13:21:13Z", "startUtcOffset": "36000s",
                             "civilStartTime": {"date": {"year": 2026, "month": 6, "day": 27}}},
                "nutrients": [{"quantity": {"grams": 11.237}, "nutrient": "PROTEIN"},
                              {"quantity": {"grams": 0.156}, "nutrient": "DIETARY_FIBER"},
                              {"quantity": {"grams": 149.76}, "nutrient": "SODIUM"}],
                "energy": {"kcal": 144},
                "totalCarbohydrate": {"grams": 4.722},
                "totalFat": {"grams": 8.596},
                "mealType": "SNACK",
                "foodDisplayName": "Chicken Thigh, Fried"}}]
    out = mapping.parse_nutrition_log(pts)
    assert len(out) == 1
    f = out[0]
    assert f["name"] == "Chicken Thigh, Fried"
    assert f["day"] == "2026-06-27"  # 13:21Z + 10h = local 27th
    assert f["calories"] == 144 and f["carbs"] == 4.722 and f["fat"] == 8.596
    assert f["protein"] == 11.2 and f["fibre"] == 0.16
    assert f["google_id"] == "7534057579911318776"  # last path segment, for dedupe
    assert f["meal_type"] == "SNACK"


def test_parse_nutrition_log_skips_non_log():
    assert mapping.parse_nutrition_log([{"name": "x", "notNutrition": {}}]) == []


def test_spo2_daily_oxygen_saturation():
    pts = [{"dataSource": {}, "dailyOxygenSaturation": {
        "date": {"year": 2026, "month": 6, "day": 27}, "averagePercentage": 96.6}}]
    out = {s["metric_id"]: s for s in mapping.to_samples("spo2", pts)}
    assert out["spo2"]["value"] == 96.6
    assert out["spo2"]["ts"] == "2026-06-27T00:00:00"


def test_parse_intraday_drop_oldest_discards_boundary_partial_day():
    pts = [
        {"steps": {"interval": {"civilStartTime": {"date": {"year": 2026, "month": 6, "day": 26}}}, "count": "6"}},
        {"steps": {"interval": {"civilStartTime": {"date": {"year": 2026, "month": 6, "day": 25}}}, "count": "4"}},
    ]
    out = {s["ts"][:10] for s in mapping.parse_intraday_daily(
        "steps", pts, "steps", "count", drop_oldest=True)}
    assert out == {"2026-06-26"}  # the oldest (page-truncated) day is dropped
    # A single-day batch is never dropped to nothing.
    one = mapping.parse_intraday_daily("steps", pts[:1], "steps", "count", drop_oldest=True)
    assert len(one) == 1


def test_parse_intraday_dedupes_repeated_datapoint_ids():
    p = {"dataPointId": "dp1",
         "steps": {"interval": {"civilStartTime": {"date": {"year": 2026, "month": 6, "day": 26}}}, "count": "6"}}
    out = mapping.parse_intraday_daily("steps", [p, p], "steps", "count")
    assert out[0]["value"] == 6.0  # paginated overlap never double-counts


def test_status_reports_missing_scopes(client):
    import datetime as dt
    from app.db import get_db
    from app.main import app as _app
    from app.models import GoogleHealthToken
    # Store a token granted BEFORE the calendar/nutrition scopes were added.
    gen = _app.dependency_overrides[get_db]()
    db = next(gen)
    db.merge(GoogleHealthToken(
        user_id="local-dev", access_token="a", refresh_token="r",
        expires_at=dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=1),
        scope="openid email profile "
              "https://www.googleapis.com/auth/googlehealth.sleep.readonly"))
    db.commit()
    r = client.get("/integrations/google/status")
    assert r.status_code == 200
    body = r.json()
    assert body["connected"] is True
    missing = body["missing_scopes"]
    assert any("nutrition" in s for s in missing)
    # Calendar is NOT a health scope any more (separate token/consent).
    assert not any("calendar" in s for s in missing)
    assert body["calendar_connected"] is False
    assert body["health_token_poisoned"] is False


def test_google_complete_reports_missing_scopes(client, monkeypatch):
    import jwt as pyjwt
    from app.integrations.google_health import oauth as gh_oauth
    id_tok = pyjwt.encode({"sub": "sub-1", "email": "t@example.com"}, "x", algorithm="HS256")
    # Google "succeeded" but silently dropped every health scope (e.g. consent
    # checkboxes unticked, or a non-Testing consent screen).
    monkeypatch.setattr(gh_oauth, "exchange_code", lambda code: {
        "access_token": "a", "refresh_token": "r", "expires_in": 3600,
        "id_token": id_tok, "scope": "openid email profile"})
    r = client.post("/auth/google/complete", json={"code": "c"})
    assert r.status_code == 200
    body = r.json()
    assert body["email"] == "t@example.com"
    assert any("googlehealth" in s for s in body["missing_scopes"])
    assert not any("calendar" in s for s in body["missing_scopes"])  # separate consent
    # And a full grant reports nothing missing.
    monkeypatch.setattr(gh_oauth, "exchange_code", lambda code: {
        "access_token": "a", "refresh_token": "r", "expires_in": 3600,
        "id_token": id_tok, "scope": " ".join(gh_oauth.SCOPES)})
    assert client.post("/auth/google/complete", json={"code": "c"}).json()["missing_scopes"] == []


def test_debug_reports_token_scopes_even_when_refresh_fails(client, monkeypatch):
    import datetime as dt
    from app.db import get_db
    from app.main import app as _app
    from app.models import GoogleHealthToken
    from app.integrations.google_health import oauth as gh_oauth, router as gh_router
    gen = _app.dependency_overrides[get_db]()
    db = next(gen)
    db.merge(GoogleHealthToken(
        user_id="local-dev", access_token="a", refresh_token="r",
        expires_at=dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=1),  # expired
        scope="openid https://www.googleapis.com/auth/googlehealth.sleep.readonly"))
    db.commit()
    monkeypatch.setattr(gh_oauth, "refresh_token",
                        lambda r: (_ for _ in ()).throw(RuntimeError("invalid_grant")))
    out = client.get("/integrations/google/debug").json()
    # The granted-scope diagnosis is returned BEFORE the refresh attempt, so an
    # expired token still shows exactly what it was allowed to do.
    assert "token_error" in out
    tok = out["_token"]
    assert "https://www.googleapis.com/auth/googlehealth.sleep.readonly" in tok["granted_scopes"]
    assert any("nutrition" in s for s in tok["missing_scopes"])


def test_status_flags_poisoned_health_token(client):
    import datetime as dt
    from app.db import get_db
    from app.main import app as _app
    from app.models import GoogleHealthToken
    gen = _app.dependency_overrides[get_db]()
    db = next(gen)
    # The pre-split token: health scopes AND calendar.events on one grant — the
    # Health API rejects it wholesale (DISALLOWED_OAUTH_SCOPES: cl_events).
    db.merge(GoogleHealthToken(
        user_id="local-dev", access_token="a", refresh_token="r",
        expires_at=dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=1),
        scope=" ".join([*oauth.SCOPES, "https://www.googleapis.com/auth/calendar.events"])))
    db.commit()
    body = client.get("/integrations/google/status").json()
    assert body["health_token_poisoned"] is True
    assert body["missing_scopes"] == []  # every health scope IS granted


def test_calendar_exchange_stores_a_separate_token(client, monkeypatch):
    import datetime as dt
    from app.db import get_db
    from app.main import app as _app
    from app.models import GoogleCalendarToken
    monkeypatch.setattr(oauth, "exchange_code", lambda code: {
        "access_token": "cal-a", "refresh_token": "cal-r", "expires_in": 3600,
        "scope": "https://www.googleapis.com/auth/calendar.events"})
    r = client.post("/integrations/google/calendar/exchange", params={"code": "c"})
    assert r.status_code == 200 and r.json()["status"] == "calendar_connected"
    gen = _app.dependency_overrides[get_db]()
    db = next(gen)
    row = db.get(GoogleCalendarToken, "local-dev")
    assert row is not None and row.refresh_token == "cal-r"
    assert "calendar.events" in (row.scope or "")


def test_calendar_push_requires_the_calendar_token(client):
    r = client.post("/me/calendar/push", json={"habits": [{"id": "h", "title": "T"}]})
    assert r.status_code == 401
    assert "calendar" in r.json()["detail"]
