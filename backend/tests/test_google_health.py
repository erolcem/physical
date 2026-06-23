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


_CST = {"year": 2026, "month": 6, "day": 20}


def test_steps_mapping_uses_sumSteps():
    pts = [{"civilStartTime": _CST, "steps": {"sumSteps": 8500}}]
    assert mapping.to_samples("steps", pts) == [{
        "metric_id": "steps", "ts": "2026-06-20T00:00:00", "value": 8500.0,
        "source": "google_health", "source_id": "steps:2026-06-20",
        "raw": {"sumSteps": 8500}}]


def test_single_value_metrics_use_first_number_fallback():
    # value lives under a type-named key (e.g. "heartRate") — parser is tolerant.
    pts = [{"civilStartTime": _CST, "heartRate": {"restingHeartRateBpm": 58}}]
    out = mapping.to_samples("resting_hr", pts)
    assert out[0]["value"] == 58.0 and out[0]["source_id"] == "resting_hr:2026-06-20"


def test_active_zone_sums_the_three_zones():
    pts = [{"civilStartTime": _CST, "activeZoneMinutes": {
        "sumInCardioHeartZone": 10, "sumInPeakHeartZone": 5, "sumInFatBurnHeartZone": 20}}]
    assert mapping.to_samples("active_zone", pts)[0]["value"] == 35.0


def test_empty_and_valueless_points_are_skipped():
    assert mapping.to_samples("steps", []) == []
    assert mapping.to_samples("hrv", [{"civilStartTime": _CST, "heartRateVariability": {}}]) == []


def test_sync_requires_a_connection(client):
    r = client.post("/integrations/google/sync", params={"user_id": "u1"})
    assert r.status_code == 404


def test_authorize_needs_client_id(client):
    r = client.get("/integrations/google/authorize",
                   params={"user_id": "u1"}, follow_redirects=False)
    assert r.status_code == 500
