"""Scheduled sync — pull every connected user's Google Health data so it stays
fresh even when no device is open. Run on a schedule on the host (e.g. a cron /
worker every few hours):

    python -m app.jobs
"""
import datetime as dt

from sqlalchemy import select

from .db import SessionLocal, init_db
from .integrations.google_health.router import sync_user
from .models import GoogleHealthToken


def sync_all(days: int = 2) -> dict:
    """Sync recent data for every user that has a Google connection."""
    init_db()
    db = SessionLocal()
    summary: dict[str, dict] = {}
    try:
        for uid in list(db.scalars(select(GoogleHealthToken.user_id))):
            res = sync_user(db, uid, days=days) or {"errors": {"none": "no token"}}
            summary[uid] = {"ingested": res.get("ingested", 0),
                            "errors": res.get("errors", {})}
    finally:
        db.close()
    return summary


if __name__ == "__main__":
    out = sync_all()
    print(f"[{dt.datetime.now(dt.timezone.utc).isoformat()}] scheduled sync: {out}")
