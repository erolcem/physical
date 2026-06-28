"""Full-snapshot backup: the app pushes a complete JSON export of its local store
(logs, habits, food, workouts, pins…) so signing in on a new device restores ALL data.
One blob per user; last write wins. Google Health data re-syncs separately."""
import datetime as dt
import json

from fastapi import APIRouter, Body, Depends, HTTPException
from sqlalchemy.orm import Session

from ..auth import current_user
from ..db import get_db
from ..models import Backup

router = APIRouter(prefix="/me/backup", tags=["backup"])


@router.put("")
def put_backup(data: dict = Body(...), user_id: str = Depends(current_user),
               db: Session = Depends(get_db)):
    """Store/replace the user's full data snapshot."""
    blob = json.dumps(data)
    db.merge(Backup(user_id=user_id, data=blob,
                    updated_at=dt.datetime.now(dt.timezone.utc)))
    db.commit()
    return {"status": "ok", "bytes": len(blob)}


@router.get("")
def get_backup(user_id: str = Depends(current_user), db: Session = Depends(get_db)):
    """Return the user's snapshot (404 if none yet) for restore on a new device."""
    row = db.get(Backup, user_id)
    if row is None:
        raise HTTPException(404, "no backup yet")
    return {"updated_at": row.updated_at.isoformat(), "data": json.loads(row.data)}
