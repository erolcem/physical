"""Pydantic request/response models."""
import datetime as dt

from pydantic import BaseModel, ConfigDict


# ── Profile ──
class ProfileIn(BaseModel):
    sex: str | None = None
    age: int | None = None
    height_cm: float | None = None
    units_pref: str = "metric"


class ProfileOut(ProfileIn):
    user_id: str
    model_config = ConfigDict(from_attributes=True)


# ── Samples ──
class SampleIn(BaseModel):
    metric_id: str
    ts: dt.datetime
    # Canonical value. For strength this is the estimated 1RM (kg); if omitted
    # and `raw` carries {weight, reps}, the server computes it via the engine.
    value: float | None = None
    bodyweight_at_ts: float | None = None
    raw: dict | None = None
    source: str = "manual"
    # Provided for idempotent re-sync (Fitbit etc.). Generated for manual logs.
    source_id: str | None = None


class SampleOut(BaseModel):
    id: int
    metric_id: str
    ts: dt.datetime
    value: float
    bodyweight_at_ts: float | None
    raw: dict | None
    source: str
    source_id: str
    model_config = ConfigDict(from_attributes=True)


class IngestResult(BaseModel):
    ingested: int
    skipped: int
    ids: list[int]


# ── Ranks ──
class MetricRank(BaseModel):
    metric_id: str
    tier: str
    sub: str
    top_pct: float
    percentile: float
    rank_value: float
    value: float
    ts: dt.datetime


class GroupRank(BaseModel):
    tier: str
    sub: str
    top_pct: float
    rank_value: float


class RanksOut(BaseModel):
    overall: GroupRank
    categories: dict[str, GroupRank]
    metrics: dict[str, MetricRank]
