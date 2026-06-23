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
    # Exactly the structure /debug returned from the live API.
    pts = [{
        "dataSource": {"platform": "FITBIT", "device": {"displayName": "Inspire 3"}},
        "dailyRestingHeartRate": {
            "date": {"year": 2026, "month": 6, "day": 23},
            "beatsPerMinute": "49",  # string, nested
            "dailyRestingHeartRateMetadata": {"calculationMethod": "WITH_SLEEP"},
        },
    }]
    out = mapping.to_samples("resting_hr", pts)
    assert out[0]["value"] == 49.0
    assert out[0]["ts"] == "2026-06-23T00:00:00"
    assert out[0]["source_id"] == "resting_hr:2026-06-23"


def test_active_zone_sums_zones_even_as_strings():
    pts = [{"dataSource": {}, "activeZoneMinutes": {
        "date": {"year": 2026, "month": 6, "day": 20},
        "sumInCardioHeartZone": "10", "sumInPeakHeartZone": "5", "sumInFatBurnHeartZone": "20"}}]
    assert mapping.to_samples("active_zone", pts)[0]["value"] == 35.0


def test_generic_single_value_metric():
    pts = [{"dataSource": {}, "dailyVo2Max": {
        "date": {"year": 2026, "month": 6, "day": 20},
        "vo2MaxMillilitersPerMinuteKilogram": "44.0"}}]
    assert mapping.to_samples("vo2max", pts)[0]["value"] == 44.0


def test_empty_and_valueless_points_are_skipped():
    assert mapping.to_samples("steps", []) == []
    assert mapping.to_samples("hrv", [{"dataSource": {}, "hrv": {
        "date": {"year": 2026, "month": 6, "day": 20}}}]) == []  # no numeric field


def test_sync_requires_a_connection(client):
    r = client.post("/integrations/google/sync", params={"user_id": "u1"})
    assert r.status_code == 404


def test_authorize_needs_client_id(client):
    r = client.get("/integrations/google/authorize",
                   params={"user_id": "u1"}, follow_redirects=False)
    assert r.status_code == 500
