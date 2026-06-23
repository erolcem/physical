"""Thin Fitbit Web API client. One method per endpoint we pull; returns the
raw JSON (mapping.py turns it into canonical samples). A 404 (no data for that
day) yields {} so a sync over empty days is harmless."""
import httpx

API = "https://api.fitbit.com"


class FitbitClient:
    def __init__(self, access_token: str):
        self._headers = {"Authorization": f"Bearer {access_token}"}

    def _get(self, path: str) -> dict:
        r = httpx.get(f"{API}{path}", headers=self._headers, timeout=20)
        if r.status_code == 200:
            return r.json()
        if r.status_code == 404:
            return {}
        r.raise_for_status()
        return {}

    def resting_hr(self, date: str) -> dict:
        return self._get(f"/1/user/-/activities/heart/date/{date}/1d.json")

    def hrv(self, date: str) -> dict:
        return self._get(f"/1/user/-/hrv/date/{date}.json")

    def cardio_score(self, date: str) -> dict:
        return self._get(f"/1/user/-/cardioscore/date/{date}.json")

    def activity(self, date: str) -> dict:
        return self._get(f"/1/user/-/activities/date/{date}.json")

    def sleep(self, date: str) -> dict:
        return self._get(f"/1.2/user/-/sleep/date/{date}.json")

    def weight(self, date: str) -> dict:
        return self._get(f"/1/user/-/body/log/weight/date/{date}/7d.json")
