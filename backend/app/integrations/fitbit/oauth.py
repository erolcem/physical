"""Fitbit OAuth 2.0 (authorization-code flow). Register a Fitbit app at
dev.fitbit.com to get the client id/secret; see backend/README.md."""
import base64
import datetime as dt
from urllib.parse import urlencode

import httpx

from ...config import settings

AUTH_URL = "https://www.fitbit.com/oauth2/authorize"
TOKEN_URL = "https://api.fitbit.com/oauth2/token"

# Everything we want — the full data range (HRV, cardio score, sleep, etc.).
SCOPES = [
    "activity", "heartrate", "sleep", "weight", "profile",
    "cardio_fitness", "respiratory_rate", "oxygen_saturation", "temperature",
]


def authorize_url(state: str) -> str:
    q = urlencode({
        "client_id": settings.fitbit_client_id,
        "response_type": "code",
        "scope": " ".join(SCOPES),
        "redirect_uri": settings.fitbit_redirect_uri,
        "state": state,
    })
    return f"{AUTH_URL}?{q}"


def _basic_auth() -> str:
    raw = f"{settings.fitbit_client_id}:{settings.fitbit_client_secret}".encode()
    return "Basic " + base64.b64encode(raw).decode()


def _token_request(data: dict) -> dict:
    r = httpx.post(
        TOKEN_URL,
        headers={"Authorization": _basic_auth(),
                 "Content-Type": "application/x-www-form-urlencoded"},
        data=data, timeout=20,
    )
    r.raise_for_status()
    return r.json()


def exchange_code(code: str) -> dict:
    return _token_request({
        "grant_type": "authorization_code", "code": code,
        "redirect_uri": settings.fitbit_redirect_uri,
        "client_id": settings.fitbit_client_id,
    })


def refresh_token(refresh: str) -> dict:
    return _token_request({"grant_type": "refresh_token", "refresh_token": refresh})


def expiry_from(token: dict) -> dt.datetime:
    secs = int(token.get("expires_in", 28800))
    return dt.datetime.now(dt.timezone.utc) + dt.timedelta(seconds=secs)
