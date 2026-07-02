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
    Connect/Connected UI), plus which of the app's scopes the stored token is
    missing — a token granted before a scope was added (calendar / nutrition)
    silently 403s those APIs until the user reconnects."""
    token = db.get(GoogleHealthToken, user_id)
    if token is None:
        return {"connected": False}
    granted = set((token.scope or "").split())
    missing = [s for s in oauth.SCOPES
               if s not in granted and s not in ("openid", "email", "profile")]
    return {"connected": True, "missing_scopes": missing}


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


@router.get("/exercises")
def google_exercises(user_id: str = Depends(current_user), db: Session = Depends(get_db)):
    """The user's recent Google exercise SESSIONS (type, duration, calories, distance,
    avg-HR, zone-minutes) for importing into the app's Exercise section."""
    token = db.get(GoogleHealthToken, user_id)
    if token is None:
        raise HTTPException(404, "Google Health not connected")
    try:
        access = _valid_access_token(db, token)
    except Exception as e:
        return {"error": str(e)[:200], "sessions": []}
    try:
        status, body = GoogleHealthClient(access).get_raw(
            "/users/me/dataTypes/exercise/dataPoints?pageSize=30")
        pts = body.get("dataPoints", []) if isinstance(body, dict) else []
    except Exception as e:
        return {"error": str(e)[:200], "sessions": []}
    return {"sessions": mapping.parse_exercise_sessions(pts)}


@router.get("/foods")
def google_foods(user_id: str = Depends(current_user), db: Session = Depends(get_db)):
    """The user's recent Google Health food logs (nutrition-log) → name + day + calories
    + macros, for importing into the Diet section. Needs the nutrition scope (reconnect)."""
    token = db.get(GoogleHealthToken, user_id)
    if token is None:
        raise HTTPException(404, "Google Health not connected")
    try:
        access = _valid_access_token(db, token)
    except Exception as e:
        return {"error": str(e)[:200], "foods": []}
    try:
        status, body = GoogleHealthClient(access).get_raw(
            "/users/me/dataTypes/nutrition-log/dataPoints?pageSize=100")
        pts = body.get("dataPoints", []) if isinstance(body, dict) else []
    except Exception as e:
        return {"error": str(e)[:200], "foods": []}
    return {"foods": mapping.parse_nutrition_log(pts)}


@router.get("/debug")
def debug(user_id: str = Depends(current_user), db: Session = Depends(get_db)):
    """Diagnose an empty sync: what does Google actually have for this account?
    Shows the profile, paired devices/data sources, and a couple of raw samples."""
    token = db.get(GoogleHealthToken, user_id)
    if token is None:
        raise HTTPException(404, "Google Health not connected")
    out = {}
    # What the stored token is actually allowed to do (scope strings only — no
    # secrets). All-403 syncs are almost always explained right here: Google
    # granted the token WITHOUT the health scopes (consent checkboxes unticked,
    # or a non-Testing/unverified consent screen silently dropping restricted
    # scopes), and no amount of reconnecting fixes that until the consent does.
    granted = set((token.scope or "").split())
    out["_token"] = {
        "granted_scopes": sorted(granted),
        "missing_scopes": [s for s in oauth.SCOPES
                           if s not in granted and s not in ("openid", "email", "profile")],
        "expires_at": str(token.expires_at),
    }
    try:
        access = _valid_access_token(db, token)
    except Exception as e:
        # If the refresh failed, re-run /authorize then /exchange to reconnect.
        out["token_error"] = str(e)[:500]
        return out
    client = GoogleHealthClient(access)
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
    # Profile (height/DOB→age). NOTE: exercise SESSIONS aren't available on this API —
    # /users/me/sessions 404s and exercise-session/activity-session/workout/session/
    # activity-summary all return 400 "Invalid data type ID" (confirmed via live debug).
    # So Google workout import isn't possible; the in-app session system is manual.
    try:
        status, body = client.get_raw("/users/me/profile")
        out["_profile"] = {"status": status, "body": body}
    except Exception as e:
        out["_profile"] = {"error": str(e)[:200]}
    # Probe whether DIET/nutrition is exposed by this API (Health Connect has a Nutrition
    # record, but this v4 REST API may not). Try the likely type IDs; a 200 with dataPoints
    # means we can auto-import food like we do exercise. (Reported under _nutrition_probe.)
    # Diet retrieval: the canonical IDs are nutrition-log / hydration-log / food (the
    # plain "nutrition" 400s). Needs the nutrition scope + food logged in Google Health.
    # daily-oxygen-saturation is the working SpO2 ID (kept for a possible background add).
    # calories/energy candidates probe for the "total energy burned" import (Part 1).
    for cand in ("nutrition-log", "hydration-log", "food", "daily-oxygen-saturation",
                 "calories", "active-energy-burned", "daily-calories", "energy-expended"):
        try:
            status, body = client.get_raw(
                f"/users/me/dataTypes/{cand}/dataPoints?pageSize=3")
            if status >= 400:
                out[f"_probe:{cand}"] = {"status": status, "error": str(body)[:200]}
            elif isinstance(body, dict):
                pts = body.get("dataPoints") or []
                out[f"_probe:{cand}"] = {"status": status, "count": len(pts),
                                         "sample": pts[0] if pts else None}
        except Exception as e:
            out[f"_probe:{cand}"] = {"error": str(e)[:200]}
    # Confirmed working type IDs: exercise (sessions), steps, heart-rate,
    # active-zone-minutes (all ported by /sync). skin-temperature + cardio-load aren't
    # exposed — cardio load is reconstructed per exercise via Edwards' TRIMP.
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

    # Resting-HR by day + a rolling baseline — feeds the sleep-score restoration term.
    rhr_by_day: dict[str, float] = {}
    try:
        for s in mapping.to_samples("resting_hr",
                                    client.query("daily-resting-heart-rate", limit=days * 2)):
            rhr_by_day[s["ts"][:10]] = s["value"]
    except Exception:
        pass
    baseline_rhr = (sum(rhr_by_day.values()) / len(rhr_by_day)) if rhr_by_day else None

    for metric_id, data_type in DATA_TYPES.items():
        try:
            pts = client.query(data_type, limit=days * 4)
            if metric_id == "sleep":
                samples += mapping.to_samples("sleep", pts,
                                              rhr_by_day=rhr_by_day, baseline_rhr=baseline_rhr)
            else:
                samples += mapping.to_samples(metric_id, pts)
        except Exception as e:  # one bad data type shouldn't sink the whole sync
            errors[data_type] = str(e)[:400]

    # Intraday → daily totals: steps + active-zone-minutes (continuous types, no daily
    # rollup). PAGINATED so a day's total covers every interval — one page of a
    # per-minute stream truncates the sums and under-counts vs the Google Health app.
    # The oldest day in the window is dropped as boundary-partial; today stays (it's a
    # live running total, refreshed by the upsert in _ingest on each sync).
    for metric_id, dtid, ckey, vkey, agg in [
        ("steps", "steps", "steps", "count", "sum"),
        ("active_zone", "active-zone-minutes", "activeZoneMinutes", "activeZoneMinutes", "sum"),
        ("heart_rate", "heart-rate", "heartRate", "beatsPerMinute", "avg"),
        # Total energy burned (PDF Part 1 diet-background). Type id unconfirmed on this
        # API — candidates probed in /debug; a 404 just yields no points (no error noise).
        ("energy_burned", "calories", "calories", "energyKcal", "sum"),
    ]:
        try:
            pts = client.query_pages(dtid)
            samples += mapping.parse_intraday_daily(metric_id, pts, ckey, vkey, agg=agg,
                                                    drop_oldest=True)
        except Exception as e:
            errors[dtid] = str(e)[:200]

    # Profile age (one value/day) → ported like everything else so the body-stats
    # card has it. Google exposes age but NOT gender/DOB — gender stays the app's
    # reference population (young male).
    try:
        _, pbody = client.get_raw("/users/me/profile")
        age = pbody.get("age") if isinstance(pbody, dict) else None
        if age is not None:
            today = dt.date.today().isoformat()
            samples.append({"metric_id": "age", "ts": f"{today}T12:00:00",
                            "value": float(age), "source": "google_health",
                            "source_id": f"age@{today}"})
    except Exception as e:
        errors["profile"] = str(e)[:200]

    try:
        ingested, skipped = _ingest(db, user_id, samples)
    except Exception as e:
        return {"pulled": len(samples), "ingested": 0, "skipped": 0,
                "errors": {**errors, "ingest": str(e)[:300]}, "days": days}
    # Classify auth-ish failures so the app can say WHAT to fix, not just "reconnect":
    #   • api_disabled  — the Google Health API is off in the Cloud project (console fix)
    #   • grant         — the token itself lacks the health scopes: Google dropped them
    #                     at consent (unticked checkboxes / consent screen not in
    #                     Testing / user not a test user) — reconnecting alone won't help
    #   • scope         — a 403 with scopes present ⇒ stale token; reconnect fixes it
    joined = " ".join(errors.values())
    if "SERVICE_DISABLED" in joined or "has not been used in project" in joined or "it is disabled" in joined:
        errors["api_disabled"] = ("the Google Health API is disabled for this Cloud "
                                  "project — enable it in console.cloud.google.com")
    elif any(("401" in v or "403" in v or "PERMISSION_DENIED" in v or "insufficient" in v.lower())
             for v in errors.values()):
        granted = set((token.scope or "").split())
        health_missing = [s for s in oauth.SCOPES if "googlehealth" in s and s not in granted]
        if health_missing:
            errors["grant"] = ("Google did not grant the health scopes at the last consent — "
                               "re-connect and TICK EVERY CHECKBOX on the consent page, and check "
                               "the OAuth consent screen is in Testing mode with your email under "
                               "Test users")
        else:
            errors["scope"] = "reconnect Google to grant the newly added permissions"
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
            # UPSERT, don't freeze: a day synced mid-day (e.g. steps at noon) or a
            # vendor-revised value (sleep score) must update, or the stored total is
            # forever whatever it was at the FIRST sync that day.
            if abs((dupe.value or 0) - float(s["value"])) > 1e-9:
                dupe.value = float(s["value"])
                dupe.raw = s.get("raw")
                ingested += 1
            else:
                skipped += 1
            continue
        db.add(Sample(
            user_id=user_id, metric_id=s["metric_id"],
            ts=dt.datetime.fromisoformat(s["ts"]), value=s["value"],
            raw=s.get("raw"), source=s["source"], source_id=s["source_id"]))
        ingested += 1
    db.commit()
    return ingested, skipped
