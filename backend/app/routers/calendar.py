"""Habit calendar feed. /me/calendar-feed gives the signed-in user their personal
subscription URL; /calendar/{token}/physical.ics serves the ICS (token-authenticated,
read from the user's latest backup blob) so any calendar app can subscribe + auto-refresh."""
import json

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlalchemy.orm import Session

from ..auth import current_user
from ..calendar_feed import build_ics, feed_token, verify_token
from ..db import get_db
from ..models import Backup

router = APIRouter(tags=["calendar"])


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
