import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import engine as E
from ..auth import current_user
from ..db import get_db
from ..models import Sample
from ..schemas import IngestResult, SampleIn, SampleOut

# All routes operate on the authenticated user (from the JWT) — never a path id —
# so a caller can only ever read/write their own data.
router = APIRouter(prefix="/me/samples", tags=["samples"])


@router.post("", response_model=IngestResult)
def ingest(body: list[SampleIn], user_id: str = Depends(current_user),
           db: Session = Depends(get_db)):
    """Bulk-ingest canonical samples. Idempotent: a sample with a `source_id`
    already seen for (user, metric, source) is skipped, so re-syncing the same
    Fitbit day never double-counts. Manual logs without a source_id get one
    generated (always inserted)."""
    ingested, skipped, ids = 0, 0, []
    for s in body:
        if s.source_id is not None:
            dupe = db.scalar(select(Sample).where(
                Sample.user_id == user_id, Sample.metric_id == s.metric_id,
                Sample.source == s.source, Sample.source_id == s.source_id))
            if dupe is not None:
                skipped += 1
                continue

        value = s.value
        if value is None:
            # Strength logged as raw {weight, reps} → estimate 1RM server-side.
            if s.raw and "weight" in s.raw and "reps" in s.raw:
                value = E.est_1rm(float(s.raw["weight"]), int(s.raw["reps"]))
            else:
                raise HTTPException(
                    status_code=422,
                    detail=f"{s.metric_id}: provide `value` or raw {{weight, reps}}")

        row = Sample(
            user_id=user_id, metric_id=s.metric_id, ts=s.ts, value=value,
            bodyweight_at_ts=s.bodyweight_at_ts, raw=s.raw, source=s.source,
            source_id=s.source_id or str(uuid.uuid4()),
        )
        db.add(row)
        db.flush()
        ids.append(row.id)
        ingested += 1

    db.commit()
    return IngestResult(ingested=ingested, skipped=skipped, ids=ids)


@router.get("", response_model=list[SampleOut])
def list_samples(
    metric_id: str | None = Query(default=None),
    source: str | None = Query(default=None),
    limit: int = Query(default=500, le=5000),
    user_id: str = Depends(current_user),
    db: Session = Depends(get_db),
):
    stmt = select(Sample).where(Sample.user_id == user_id)
    if metric_id:
        stmt = stmt.where(Sample.metric_id == metric_id)
    if source:
        stmt = stmt.where(Sample.source == source)
    stmt = stmt.order_by(Sample.ts.desc()).limit(limit)
    return list(db.scalars(stmt))
