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
