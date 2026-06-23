"""Google OAuth 2.0 for the Google Health API. Register an OAuth client in the
Google Cloud Console (Web Server type); see backend/README.md.

`access_type=offline` + `prompt=consent` are required to receive a refresh token.
In OAuth 'testing' mode those refresh tokens expire after 7 days (Google).
"""
import datetime as dt
from urllib.parse import urlencode

import httpx

from ...config import settings

AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"

# Read-only Google Health API scopes covering the full data range we want.
SCOPES = [
    "https://www.googleapis.com/auth/googlehealth.profile.readonly",
    "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly",
    "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly",
    "https://www.googleapis.com/auth/googlehealth.sleep.readonly",
]


def authorize_url(state: str) -> str:
    q = urlencode({
        "client_id": settings.google_client_id,
        "response_type": "code",
        "scope": " ".join(SCOPES),
        "redirect_uri": settings.google_redirect_uri,
        "state": state,
        "access_type": "offline",
        "prompt": "consent",
        "include_granted_scopes": "true",
    })
    return f"{AUTH_URL}?{q}"


def _token_request(data: dict) -> dict:
    r = httpx.post(TOKEN_URL, data={
        **data,
        "client_id": settings.google_client_id,
        "client_secret": settings.google_client_secret,
    }, timeout=20)
    r.raise_for_status()
    return r.json()


def exchange_code(code: str) -> dict:
    return _token_request({
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": settings.google_redirect_uri,
    })


def refresh_token(refresh: str) -> dict:
    # Google omits refresh_token on refresh responses — caller keeps the old one.
    return _token_request({"grant_type": "refresh_token", "refresh_token": refresh})


def expiry_from(token: dict) -> dt.datetime:
    secs = int(token.get("expires_in", 3600))
    return dt.datetime.now(dt.timezone.utc) + dt.timedelta(seconds=secs)
