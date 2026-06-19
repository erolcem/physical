from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Profile
from ..schemas import ProfileIn, ProfileOut

router = APIRouter(prefix="/users/{user_id}/profile", tags=["profile"])


@router.put("", response_model=ProfileOut)
def upsert_profile(user_id: str, body: ProfileIn, db: Session = Depends(get_db)):
    row = db.get(Profile, user_id)
    if row is None:
        row = Profile(user_id=user_id)
        db.add(row)
    row.sex = body.sex
    row.age = body.age
    row.height_cm = body.height_cm
    row.units_pref = body.units_pref
    db.commit()
    db.refresh(row)
    return row


@router.get("", response_model=ProfileOut)
def get_profile(user_id: str, db: Session = Depends(get_db)):
    row = db.get(Profile, user_id)
    if row is None:
        raise HTTPException(status_code=404, detail="profile not found")
    return row
