from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..auth import current_user
from ..db import get_db
from ..models import Profile
from ..schemas import ProfileIn, ProfileOut

router = APIRouter(prefix="/me/profile", tags=["profile"])


@router.put("", response_model=ProfileOut)
def upsert_profile(body: ProfileIn, user_id: str = Depends(current_user),
                   db: Session = Depends(get_db)):
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
def get_profile(user_id: str = Depends(current_user), db: Session = Depends(get_db)):
    row = db.get(Profile, user_id)
    if row is None:
        raise HTTPException(status_code=404, detail="profile not found")
    return row
