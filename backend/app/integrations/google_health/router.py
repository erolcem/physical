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
from fastapi.responses import RedirectResponse
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from ...config import settings
from ...db import get_db
from ...models import GoogleHealthToken, Sample
from . import mapping, oauth
from .client import DATA_TYPES, GoogleHealthClient

router = APIRouter(prefix="/integrations/google", tags=["google-health"])


@router.get("/authorize")
def authorize(user_id: str = Query(...)):
    if not settings.google_client_id:
        raise HTTPException(500, "GOOGLE_CLIENT_ID not configured (see backend/README.md)")
    return RedirectResponse(oauth.authorize_url(state=user_id))


@router.post("/exchange")
def exchange(user_id: str = Query(...), code: str = Query(...),
             db: Session = Depends(get_db)):
    _store_token(db, user_id, oauth.exchange_code(code))
    return {"status": "connected", "user_id": user_id}


@router.get("/debug")
def debug(user_id: str = Query(...), db: Session = Depends(get_db)):
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
            if isinstance(body, dict):
                pts = body.get("dataPoints") or []
                sample = pts[0] if pts else {"_no_dataPoints": True, "keys": list(body.keys())}
            else:
                sample = str(body)[:300]
            out[metric_id] = {"status": status, "sample": sample}
        except Exception as e:
            out[metric_id] = {"error": str(e)[:300]}
    return out


@router.post("/sync")
def sync(user_id: str = Query(...), days: int = Query(7, ge=1, le=30),
         replace: bool = Query(False, description="delete existing Google samples first"),
         db: Session = Depends(get_db)):
    token = db.get(GoogleHealthToken, user_id)
    if token is None:
        raise HTTPException(404, "Google Health not connected — run /authorize then /exchange")
    if replace:
        # Lets corrected mappings overwrite previously-ingested (possibly wrong) values.
        db.execute(delete(Sample).where(
            Sample.user_id == user_id, Sample.source == "google_health"))
        db.commit()
    try:
        access = _valid_access_token(db, token)
    except Exception as e:
        # Always return JSON (never a bare 500), so the client sees the reason.
        return {"pulled": 0, "ingested": 0, "skipped": 0,
                "errors": {"token": f"refresh failed: {str(e)[:300]}"}, "days": days}
    client = GoogleHealthClient(access)

    samples: list[dict] = []
    errors: dict[str, str] = {}
    for metric_id, data_type in DATA_TYPES.items():
        if metric_id == "sleep":
            continue  # sleep rollup shape is verified live before mapping
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
