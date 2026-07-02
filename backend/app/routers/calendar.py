"""Habit calendar. Two ways onto the user's calendar:
  • /me/calendar/push — writes habits straight into Google Calendar via the Calendar API
    (automatic; needs the calendar.events scope — re-consent).
  • /me/calendar-feed + /calendar/{token}/physical.ics — a subscription feed fallback for
    any calendar app (no extra scope)."""
import json

import httpx
from fastapi import APIRouter, Body, Depends, HTTPException, Request, Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..auth import current_user
from ..calendar_feed import build_ics, feed_token, habit_event, verify_token
from ..db import get_db
from ..integrations.google_health.router import _valid_access_token
from ..models import Backup, GoogleCalendarToken

router = APIRouter(tags=["calendar"])

_CAL = "https://www.googleapis.com/calendar/v3/calendars/primary/events"


@router.post("/me/calendar/push")
def push_to_google_calendar(
    body: dict = Body(...),
    user_id: str = Depends(current_user),
    db: Session = Depends(get_db),
):
    """Upsert the app-supplied habits as recurring events in the user's Google Calendar.
    Tagged with a private extended property so re-pushes update (never duplicate), and
    habits that no longer exist are removed. Returns {added, updated, removed}.

    Uses the SEPARATE calendar token (from /integrations/google/calendar/exchange):
    the calendar grant can't ride on the health token — health.googleapis.com rejects
    tokens carrying calendar.events (DISALLOWED_OAUTH_SCOPES)."""
    token = db.get(GoogleCalendarToken, user_id)
    if not token:
        raise HTTPException(401, "needs_calendar_connect")
    try:
        access = _valid_access_token(db, token)
    except Exception:
        raise HTTPException(401, "needs_reconnect")
    habits = [h for h in (body.get("habits") or []) if isinstance(h, dict)]
    tz = body.get("tz")
    headers = {"Authorization": f"Bearer {access}"}

    # Existing Physical events on the calendar, keyed by habit id.
    try:
        existing: dict[str, str] = {}
        page = None
        while True:
            params = {"privateExtendedProperty": "app=physical", "maxResults": 250,
                      "showDeleted": "false"}
            if page:
                params["pageToken"] = page
            r = httpx.get(_CAL, headers=headers, params=params, timeout=30)
            if r.status_code == 403:
                raise HTTPException(403, "needs_reconnect")  # calendar scope not granted
            if r.status_code >= 400:
                raise HTTPException(502, f"Calendar list failed: {r.text[:200]}")
            data = r.json()
            for ev in data.get("items", []):
                hid = ev.get("extendedProperties", {}).get("private", {}).get("habit")
                if hid:
                    existing[hid] = ev["id"]
            page = data.get("nextPageToken")
            if not page:
                break
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(502, f"Calendar unavailable: {str(e)[:160]}")

    added = updated = removed = 0
    seen: set[str] = set()
    for h in habits:
        hid = str(h.get("id") or h.get("title") or "")
        if not hid:
            continue
        seen.add(hid)
        ev = habit_event(h, tz=tz)
        if hid in existing:
            r = httpx.put(f"{_CAL}/{existing[hid]}", headers=headers, json=ev, timeout=30)
            if r.status_code < 400:
                updated += 1
        else:
            r = httpx.post(_CAL, headers=headers, json=ev, timeout=30)
            if r.status_code < 400:
                added += 1
    # Remove events for habits that no longer exist.
    for hid, eid in existing.items():
        if hid not in seen:
            r = httpx.delete(f"{_CAL}/{eid}", headers=headers, timeout=30)
            if r.status_code < 400 or r.status_code == 410:
                removed += 1
    return {"added": added, "updated": updated, "removed": removed}


@router.get("/me/calendar-feed")
def calendar_feed(request: Request, user_id: str = Depends(current_user)):
    base = str(request.base_url).rstrip("/")
    return {"url": f"{base}/calendar/{feed_token(user_id)}/physical.ics"}


@router.get("/calendar/{token}/physical.ics")
def habits_ics(token: str, db: Session = Depends(get_db)):
    user_id = verify_token(token)
    if not user_id:
        raise HTTPException(404, "Unknown calendar feed")
    row = db.get(Backup, user_id)
    habits: list[dict] = []
    if row:
        try:
            habits = (json.loads(row.data) or {}).get("habits", []) or []
        except Exception:
            habits = []
    return Response(
        content=build_ics(habits),
        media_type="text/calendar; charset=utf-8",
        headers={"Content-Disposition": 'inline; filename="physical.ics"'},
    )
