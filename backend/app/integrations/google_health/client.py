"""Thin Google Health API (v4) client.

The v4 API is a generic dataType/dataPoint model: you query daily-aggregated
dataPoints per dataType. The dataType identifiers and base URL below are from the
official discovery doc; the exact request body + response field paths for
`dataPoints:dailyRollUp` are confirmed on the first live sync (Google's public
docs don't fully specify them), which is why mapping.py uses a tolerant parser.
"""
import datetime as dt

import httpx

BASE = "https://health.googleapis.com/v4"

# canonical metric_id → Google Health dataType identifier (from the v4 discovery doc)
DATA_TYPES = {
    "resting_hr": "daily-resting-heart-rate",
    "hrv": "daily-heart-rate-variability",
    "vo2max": "daily-vo2-max",
    "steps": "steps",
    "active_zone": "active-zone-minutes",
    "energy_burned": "active-energy-burned",
    "bodyweight": "weight",
    "body_fat_pct": "body-fat",
    "sleep": "sleep",
}


class GoogleHealthClient:
    def __init__(self, access_token: str):
        self._headers = {"Authorization": f"Bearer {access_token}"}

    def daily_rollup(self, data_type: str, days: int) -> list[dict]:
        end = dt.date.today()
        start = end - dt.timedelta(days=days)
        url = f"{BASE}/users/me/dataTypes/{data_type}/dataPoints:dailyRollUp"
        # The endpoint takes a CivilTimeInterval `range`, not start/end timestamps.
        body = {"range": {
            "start": {"year": start.year, "month": start.month, "day": start.day},
            "end": {"year": end.year, "month": end.month, "day": end.day},
        }}
        r = httpx.post(url, headers=self._headers, json=body, timeout=30)
        if r.status_code == 404:
            return []
        if r.status_code >= 400:
            # Surface Google's actual error message instead of a bare 500.
            raise RuntimeError(f"{r.status_code} {r.text[:400]}")
        return r.json().get("rollupDataPoints", [])
