"""Fitbit (Google Health) cloud adapter endpoints:

  GET  /integrations/fitbit/authorize?user_id=...   → redirect to Fitbit consent
  GET  /integrations/fitbit/callback?code=&state=   → store tokens (OAuth return)
  POST /integrations/fitbit/sync?user_id=&days=N     → pull N days, map, ingest

The pulled data lands in the same canonical sample store as manual logs, deduped
on (user, metric, source='fitbit', source_id), so re-syncing never double-counts.
"""
import datetime as dt
import secrets

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import RedirectResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from ...config import settings
from ...db import get_db
from ...models import FitbitToken, Sample
from . import mapping, oauth
from .client import FitbitClient

router = APIRouter(prefix="/integrations/fitbit", tags=["fitbit"])

# Dev-simple CSRF state → user map for the OAuth round trip.
_pending_states: dict[str, str] = {}


@router.get("/authorize")
def authorize(user_id: str = Query(...)):
    if not settings.fitbit_client_id:
        raise HTTPException(500, "FITBIT_CLIENT_ID not configured (see backend/README.md)")
    state = secrets.token_urlsafe(16)
    _pending_states[state] = user_id
    return RedirectResponse(oauth.authorize_url(state))


@router.get("/callback")
def callback(code: str = Query(...), state: str = Query(...), db: Session = Depends(get_db)):
    user_id = _pending_states.pop(state, None)
    if user_id is None:
        raise HTTPException(400, "unknown or expired OAuth state")
    _store_token(db, user_id, oauth.exchange_code(code))
    return {"status": "connected", "user_id": user_id,
            "next": f"POST /users/{user_id}/... or /integrations/fitbit/sync?user_id={user_id}"}


@router.post("/sync")
def sync(user_id: str = Query(...), days: int = Query(7, ge=1, le=90),
         db: Session = Depends(get_db)):
    token = db.get(FitbitToken, user_id)
    if token is None:
        raise HTTPException(404, "Fitbit not connected — open /integrations/fitbit/authorize first")
    client = FitbitClient(_valid_access_token(db, token))

    today = dt.date.today()
    samples: list[dict] = []
    for i in range(days):
        d = (today - dt.timedelta(days=i)).isoformat()
        samples += mapping.map_resting_hr(client.resting_hr(d))
        samples += mapping.map_hrv(client.hrv(d))
        samples += mapping.map_cardio_score(client.cardio_score(d))
        samples += mapping.map_activity(client.activity(d), d)
        samples += mapping.map_sleep(client.sleep(d))
    samples += mapping.map_weight(client.weight(today.isoformat()))

    ingested, skipped = _ingest(db, user_id, samples)
    return {"pulled": len(samples), "ingested": ingested, "skipped": skipped, "days": days}


# ── helpers ──
def _store_token(db: Session, user_id: str, tok: dict) -> None:
    db.merge(FitbitToken(
        user_id=user_id,
        access_token=tok["access_token"],
        refresh_token=tok["refresh_token"],
        expires_at=oauth.expiry_from(tok),
        scope=tok.get("scope"),
        fitbit_user_id=tok.get("user_id"),
    ))
    db.commit()


def _valid_access_token(db: Session, token: FitbitToken) -> str:
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
    for s in samples:
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
