"""Habit calendar. Two ways onto the user's calendar:
  • /me/calendar/push — writes habits straight into Google Calendar via the Calendar API
    (automatic; needs the calendar.events scope — re-consent).
  • /me/calendar-feed + /calendar/{token}/physical.ics — a subscription feed fallback for
    any calendar app (no extra scope)."""
import hashlib
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


def habit_event_id(habit_id: str) -> str:
    """The DETERMINISTIC Google Calendar event id for a habit. The Calendar API
    lets the caller choose the event id (base32hex charset — sha1 hexdigest is a
    subset), so one habit can only ever occupy one event slot: concurrent pushes
    (connect-flow + sync + habit-change debounce) collide on the same id instead
    of each inserting their own copy. This is what makes duplicates impossible
    by construction, rather than relying on list-then-insert (whose read can
    race other writers AND Google's eventually-consistent search index)."""
    return "ph" + hashlib.sha1(f"physical:{habit_id}".encode()).hexdigest()


@router.post("/me/calendar/push")
def push_to_google_calendar(
    body: dict = Body(...),
    user_id: str = Depends(current_user),
    db: Session = Depends(get_db),
):
    """Reconcile the app-supplied habits with the user's Google Calendar:
    one deterministic event per habit (insert-or-update, resurrecting a
    previously-deleted slot), any stray copies of a habit deleted (heals
    calendars that were duplicated by older racy pushes), and events for
    habits that no longer exist removed. Returns {added, updated, removed,
    deduped, failed[, error]}.

    Uses the SEPARATE calendar token (from /integrations/google/calendar/exchange):
    the calendar grant can't ride on the health token — health.googleapis.com rejects
    tokens carrying calendar.events (DISALLOWED_OAUTH_SCOPES)."""
    token = db.get(GoogleCalendarToken, user_id)
    if not token:
        raise HTTPException(401, "needs_calendar_connect")
    try:
        access = _valid_access_token(db, token)
    except Exception as e:
        # Only a DEAD grant (revoked / 7-day testing expiry → invalid_grant)
        # means "reconnect". A transient refresh failure is a retry, not a
        # re-consent — mislabelling it sent users to a reconnect that fixed
        # nothing.
        if "invalid_grant" in str(e):
            raise HTTPException(401, "needs_reconnect")
        raise HTTPException(502, f"calendar token refresh failed: {str(e)[:160]}")
    # Archived (retired) habits are history — they must never (re)appear as
    # calendar events, whichever caller sends them. Filtering here also prunes
    # their existing events via the reconcile pass below.
    habits = [h for h in (body.get("habits") or [])
              if isinstance(h, dict) and not h.get("arch")]
    tz = body.get("tz")
    headers = {"Authorization": f"Bearer {access}"}

    # Every Physical event currently on the calendar, keyed by habit id — a habit
    # can (wrongly) own several from older racy pushes; keep them ALL so the
    # reconcile pass below can delete the strays.
    try:
        existing: dict[str, list[str]] = {}
        page = None
        while True:
            params = {"privateExtendedProperty": "app=physical", "maxResults": 250,
                      "showDeleted": "false"}
            if page:
                params["pageToken"] = page
            r = httpx.get(_CAL, headers=headers, params=params, timeout=30)
            if r.status_code == 403:
                # Distinguish "the Calendar API is switched off in the Cloud
                # project" (a console fix — reconnecting can never help) from a
                # genuine missing grant.
                if "SERVICE_DISABLED" in r.text or "has not been used in project" in r.text:
                    raise HTTPException(412, "calendar_api_disabled: enable the "
                                        "Google Calendar API for your Cloud project "
                                        "(console.cloud.google.com → APIs & Services "
                                        "→ Library → Google Calendar API → Enable)")
                raise HTTPException(403, "needs_reconnect")  # calendar scope not granted
            if r.status_code >= 400:
                raise HTTPException(502, f"Calendar list failed: {r.text[:200]}")
            data = r.json()
            for ev in data.get("items", []):
                hid = ev.get("extendedProperties", {}).get("private", {}).get("habit")
                if hid:
                    existing.setdefault(hid, []).append(ev["id"])
            page = data.get("nextPageToken")
            if not page:
                break
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(502, f"Calendar unavailable: {str(e)[:160]}")

    def _delete(eid: str) -> bool:
        r = httpx.delete(f"{_CAL}/{eid}", headers=headers, timeout=30)
        return r.status_code < 400 or r.status_code == 410

    added = updated = removed = deduped = failed = 0
    first_error: str | None = None
    seen: set[str] = set()
    for h in habits:
        hid = str(h.get("id") or h.get("title") or "")
        if not hid:
            continue
        seen.add(hid)
        eid = habit_event_id(hid)
        ev = habit_event(h, tz=tz)
        # Fixed id + confirmed status: an insert that collides (already exists,
        # or exists as a previously-deleted "cancelled" slot) falls through to
        # an update that also resurrects it.
        ev["id"] = eid
        ev["status"] = "confirmed"
        canonical_exists = eid in existing.get(hid, [])
        if canonical_exists:
            r = httpx.put(f"{_CAL}/{eid}", headers=headers, json=ev, timeout=30)
        else:
            r = httpx.post(_CAL, headers=headers, json=ev, timeout=30)
            if r.status_code == 409:  # id taken (concurrent push / cancelled slot)
                r = httpx.put(f"{_CAL}/{eid}", headers=headers, json=ev, timeout=30)
                canonical_exists = True
        if r.status_code < 400:
            if canonical_exists:
                updated += 1
            else:
                added += 1
            # Heal duplicates: any OTHER event claiming this habit (legacy
            # random-id events, racy copies) is a stray — delete it.
            for stray in existing.get(hid, []):
                if stray != eid and _delete(stray):
                    deduped += 1
        else:
            # Don't swallow per-event failures — a systematic one (e.g. a missing
            # timeZone on recurring events) used to report "synced" with an
            # empty calendar. Surface the first Google error to the app.
            failed += 1
            if first_error is None:
                first_error = r.text[:200]
    # Remove events for habits that no longer exist.
    for hid, eids in existing.items():
        if hid not in seen:
            for eid in eids:
                if _delete(eid):
                    removed += 1
    out: dict = {"added": added, "updated": updated, "removed": removed,
                 "deduped": deduped, "failed": failed}
    if first_error:
        out["error"] = first_error
    return out


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
