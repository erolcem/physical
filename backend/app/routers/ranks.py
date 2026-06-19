from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Sample
from ..ranking import compute_ranks
from ..schemas import RanksOut

router = APIRouter(prefix="/users/{user_id}/ranks", tags=["ranks"])


@router.get("", response_model=RanksOut)
def get_ranks(user_id: str, db: Session = Depends(get_db)):
    """Overall + per-category + per-metric ranks, computed from the user's
    stored samples by the canonical engine (latest value per metric, strength
    scored at its bodyweight-at-time)."""
    samples = list(db.scalars(select(Sample).where(Sample.user_id == user_id)))
    overall, categories, metrics = compute_ranks(samples)
    return RanksOut(overall=overall, categories=categories, metrics=metrics)
