"""Google Health API cloud adapter endpoints:

  GET  /integrations/google/authorize?user_id=...     → redirect to Google consent
  POST /integrations/google/exchange?user_id=&code=   → paste the code, store tokens
  POST /integrations/google/sync?user_id=&days=N       → pull N days, map, ingest

Because the registered redirect URI is https://www.google.com, after consent the
`code` lands in that page's URL — copy it and POST it to /exchange. Pulled data
lands in the canonical store deduped on (user, metric, source='google_health',
source_id), so re-syncing never double-counts.
"""
import datetime as dt

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from ...auth import current_user
from ...config import settings
from ...db import get_db
from ...models import GoogleHealthToken, Sample
from . import mapping, oauth
from .client import DATA_TYPES, GoogleHealthClient

# Every endpoint binds to the signed-in user, so each person connects and syncs
# their own Google account into their own isolated data.
router = APIRouter(prefix="/integrations/google", tags=["google-health"])


@router.get("/authorize")
def authorize(user_id: str = Depends(current_user)):
    """Return the Google consent URL for the signed-in user to open. (The app
    calls this with its token, then opens the URL in a browser/webview.)"""
    if not settings.google_client_id:
        raise HTTPException(500, "GOOGLE_CLIENT_ID not configured (see backend/README.md)")
    return {"authorize_url": oauth.authorize_url(state=user_id)}


@router.post("/exchange")
def exchange(code: str = Query(...), user_id: str = Depends(current_user),
             db: Session = Depends(get_db)):
    _store_token(db, user_id, oauth.exchange_code(code))
    return {"status": "connected", "user_id": user_id}


@router.get("/status")
def status(user_id: str = Depends(current_user), db: Session = Depends(get_db)):
    """Whether the signed-in user has a Google Health connection (for the app's
    Connect/Connected UI)."""
    return {"connected": db.get(GoogleHealthToken, user_id) is not None}


@router.get("/profile")
def google_profile(user_id: str = Depends(current_user), db: Session = Depends(get_db)):
    """The user's Google Health profile (age) for auto-porting into the app profile.
    Google exposes age here but not height/DOB/gender — those stay manual."""
    token = db.get(GoogleHealthToken, user_id)
    if token is None:
        raise HTTPException(404, "Google Health not connected")
    try:
        access = _valid_access_token(db, token)
    except Exception as e:
        return {"error": str(e)[:200]}
    status, body = GoogleHealthClient(access).get_raw("/users/me/profile")
    if status != 200 or not isinstance(body, dict):
        return {}
    return {"age": body.get("age")}


@router.get("/debug")
def debug(user_id: str = Depends(current_user), db: Session = Depends(get_db)):
    """Diagnose an empty sync: what does Google actually have for this account?
    Shows the profile, paired devices/data sources, and a couple of raw samples."""
    token = db.get(GoogleHealthToken, user_id)
    if token is None:
        raise HTTPException(404, "Google Health not connected")
    try:
        access = _valid_access_token(db, token)
    except Exception as e:
        # If the refresh failed, re-run /authorize then /exchange to reconnect.
        return {"token_error": str(e)[:500]}
    client = GoogleHealthClient(access)
    out = {}
    # One real sample per data type so we can write precise field extractors.
    for metric_id, data_type in DATA_TYPES.items():
        try:
            status, body = client.get_raw(
                f"/users/me/dataTypes/{data_type}/dataPoints?pageSize=10")
            if status >= 400:
                # Surface Google's actual error (it usually names the valid type).
                out[metric_id] = {"status": status, "error": body}
            elif isinstance(body, dict):
                pts = body.get("dataPoints") or []
                out[metric_id] = {"status": status,
                                  "sample": pts[0] if pts else {"_no_dataPoints": True, "keys": list(body.keys())}}
            else:
                out[metric_id] = {"status": status, "sample": str(body)[:300]}
        except Exception as e:
            out[metric_id] = {"error": str(e)[:300]}
    # Profile (height/DOB→age) + a hunt for an EXERCISE-SESSION endpoint (none found
    # on /sessions yet). Several candidate paths are probed; whichever returns 200
    # with data is the one to wire for porting Google workouts.
    probes = {
        "_profile": "/users/me/profile",
        "_sessions": "/users/me/sessions?pageSize=3",
        "_sess_exercise": "/users/me/dataTypes/exercise-session/dataPoints?pageSize=3",
        "_sess_activity": "/users/me/dataTypes/activity-session/dataPoints?pageSize=3",
        "_sess_workout": "/users/me/dataTypes/workout/dataPoints?pageSize=3",
        "_sess_activity_summary": "/users/me/dataTypes/activity-summary/dataPoints?pageSize=3",
        "_sess_session": "/users/me/dataTypes/session/dataPoints?pageSize=3",
    }
    for label, path in probes.items():
        try:
            status, body = client.get_raw(path)
            # Show full body for success; just the error text for failures.
            out[label] = {"status": status, "body": body if status < 400 else str(body)[:200]}
        except Exception as e:
            out[label] = {"error": str(e)[:200]}
    return out


def sync_user(db: Session, user_id: str, days: int = 7, replace: bool = False) -> dict | None:
    """Core sync: pull the user's Google Health data and ingest it. Returns the
    result dict, or None if the user has no Google connection. Never raises on
    token/data issues (collected into `errors`) — safe for the scheduled job too.
    """
    token = db.get(GoogleHealthToken, user_id)
    if token is None:
        return None
    if replace:
        db.execute(delete(Sample).where(
            Sample.user_id == user_id, Sample.source == "google_health"))
        db.commit()
    try:
        access = _valid_access_token(db, token)
    except Exception as e:
        return {"pulled": 0, "ingested": 0, "skipped": 0,
                "errors": {"token": f"refresh failed: {str(e)[:300]}"}, "days": days}
    client = GoogleHealthClient(access)

    samples: list[dict] = []
    errors: dict[str, str] = {}
    for metric_id, data_type in DATA_TYPES.items():
        try:
            samples += mapping.to_samples(metric_id, client.query(data_type, limit=days * 4))
        except Exception as e:  # one bad data type shouldn't sink the whole sync
            errors[data_type] = str(e)[:400]

    try:
        ingested, skipped = _ingest(db, user_id, samples)
    except Exception as e:
        return {"pulled": len(samples), "ingested": 0, "skipped": 0,
                "errors": {**errors, "ingest": str(e)[:300]}, "days": days}
    return {"pulled": len(samples), "ingested": ingested, "skipped": skipped,
            "errors": errors, "days": days}


@router.post("/sync")
def sync(days: int = Query(7, ge=1, le=30),
         replace: bool = Query(False, description="delete existing Google samples first"),
         user_id: str = Depends(current_user),
         db: Session = Depends(get_db)):
    result = sync_user(db, user_id, days, replace)
    if result is None:
        raise HTTPException(404, "Google Health not connected — sign in with Google first")
    return result


# ── helpers ──
def _store_token(db: Session, user_id: str, tok: dict) -> None:
    existing = db.get(GoogleHealthToken, user_id)
    # Google omits refresh_token on refresh responses — keep the stored one.
    refresh = tok.get("refresh_token") or (existing.refresh_token if existing else None)
    if not refresh:
        raise HTTPException(400, "no refresh_token returned — re-consent (prompt=consent)")
    db.merge(GoogleHealthToken(
        user_id=user_id, access_token=tok["access_token"], refresh_token=refresh,
        expires_at=oauth.expiry_from(tok), scope=tok.get("scope")))
    db.commit()


def _valid_access_token(db: Session, token: GoogleHealthToken) -> str:
    exp = token.expires_at
    if exp.tzinfo is None:
        exp = exp.replace(tzinfo=dt.timezone.utc)
    if exp <= dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=2):
        new = oauth.refresh_token(token.refresh_token)
        _store_token(db, token.user_id, new)
        return new["access_token"]
    return token.access_token


def _ingest(db: Session, user_id: str, samples: list[dict]) -> tuple[int, int]:
    ingested = skipped = 0
    seen: set[tuple] = set()  # de-dupe within this batch (Google returns several
    for s in samples:         # points per metric+day; source_id collapses them)
        key = (s["metric_id"], s["source"], s["source_id"])
        if key in seen:
            skipped += 1
            continue
        seen.add(key)
        dupe = db.scalar(select(Sample).where(
            Sample.user_id == user_id, Sample.metric_id == s["metric_id"],
            Sample.source == s["source"], Sample.source_id == s["source_id"]))
        if dupe is not None:
            skipped += 1
            continue
        db.add(Sample(
            user_id=user_id, metric_id=s["metric_id"],
            ts=dt.datetime.fromisoformat(s["ts"]), value=s["value"],
            raw=s.get("raw"), source=s["source"], source_id=s["source_id"]))
        ingested += 1
    db.commit()
    return ingested, skipped
