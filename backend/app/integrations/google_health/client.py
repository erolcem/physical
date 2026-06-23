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

    def query(self, data_type: str, limit: int = 100) -> list[dict]:
        """List recent dataPoints for a dataType (GET). Simpler and more robust
        than the dailyRollUp custom method (whose CivilDateTime body shape isn't
        publicly specified). Date-range filtering is a later refinement; for the
        daily-* types each dataPoint is already one day's value."""
        url = f"{BASE}/users/me/dataTypes/{data_type}/dataPoints"
        r = httpx.get(url, headers=self._headers, params={"pageSize": limit}, timeout=30)
        if r.status_code == 404:
            return []
        if r.status_code >= 400:
            # Surface Google's actual error message instead of a bare 500.
            raise RuntimeError(f"{r.status_code} {r.text[:400]}")
        return r.json().get("dataPoints", [])

    def get_raw(self, path: str):
        """Raw GET for diagnostics — returns (status_code, parsed-json-or-text)."""
        r = httpx.get(f"{BASE}{path}", headers=self._headers, timeout=20)
        try:
            return r.status_code, r.json()
        except Exception:
            return r.status_code, r.text[:600]
