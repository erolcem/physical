"""Fitbit JSON → canonical sample mapping, with fixtures shaped like the real
Fitbit Web API responses. Pure logic — no network."""
from app.integrations.fitbit import mapping as M


def test_resting_hr():
    data = {"activities-heart": [
        {"dateTime": "2026-06-20", "value": {"restingHeartRate": 58}}]}
    out = M.map_resting_hr(data)
    assert out == [{"metric_id": "resting_hr", "ts": "2026-06-20T00:00:00",
                    "value": 58.0, "source": "fitbit",
                    "source_id": "resting_hr:2026-06-20",
                    "raw": {"restingHeartRate": 58}}]


def test_hrv():
    data = {"hrv": [{"dateTime": "2026-06-20", "value": {"dailyRmssd": 34.5, "deepRmssd": 31.2}}]}
    out = M.map_hrv(data)
    assert len(out) == 1 and out[0]["metric_id"] == "hrv" and out[0]["value"] == 34.5
    assert out[0]["source_id"] == "hrv:2026-06-20"


def test_cardio_score_range_takes_midpoint():
    data = {"cardioScore": [{"dateTime": "2026-06-20", "value": {"vo2Max": "42-46"}}]}
    out = M.map_cardio_score(data)
    assert out[0]["metric_id"] == "vo2max" and out[0]["value"] == 44.0


def test_cardio_score_single_value():
    data = {"cardioScore": [{"dateTime": "2026-06-20", "value": {"vo2Max": 48}}]}
    assert M.map_cardio_score(data)[0]["value"] == 48.0


def test_activity_steps_calories_azm():
    data = {"summary": {"steps": 8500, "caloriesOut": 2400,
                        "activeZoneMinutes": {"activeZoneMinutes": 35}}}
    out = {s["metric_id"]: s for s in M.map_activity(data, "2026-06-20")}
    assert out["steps"]["value"] == 8500.0
    assert out["energy_burned"]["value"] == 2400.0
    assert out["active_zone"]["value"] == 35.0


def test_weight_and_bodyfat():
    data = {"weight": [{"date": "2026-06-20", "time": "08:00:00", "weight": 78.5, "fat": 15.2}]}
    out = {s["metric_id"]: s for s in M.map_weight(data)}
    assert out["bodyweight"]["value"] == 78.5
    assert out["bodyweight"]["ts"] == "2026-06-20T08:00:00"
    assert out["body_fat_pct"]["value"] == 15.2


def test_sleep_efficiency_stages_duration():
    data = {"sleep": [{
        "dateOfSleep": "2026-06-20", "efficiency": 92, "minutesAsleep": 420,
        "levels": {"summary": {"deep": {"minutes": 80}, "rem": {"minutes": 95}}},
    }]}
    out = {s["metric_id"]: s for s in M.map_sleep(data)}
    assert out["sleep_efficiency"]["value"] == 92.0
    assert out["deep_sleep"]["value"] == 80.0
    assert out["rem_sleep"]["value"] == 95.0
    assert out["sleep_duration"]["value"] == 7.0  # 420 min → hours


def test_empty_payloads_are_safe():
    assert M.map_resting_hr({}) == []
    assert M.map_hrv({"hrv": []}) == []
    assert M.map_sleep({"sleep": []}) == []
