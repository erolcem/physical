"""Pydantic request/response models."""
import datetime as dt

from pydantic import BaseModel, ConfigDict


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


# ── AI coach (PDF Part 5) ──
class CoachTurn(BaseModel):
    role: str  # "user" | "model"
    text: str


class CoachChatIn(BaseModel):
    message: str
    history: list[CoachTurn] = []
    habits: list[dict] = []  # app-supplied: {title, category?, done_today?, streak?}
    profile: dict | None = None
    diet: dict | None = None        # today's totals: {calories, protein, carbs, fat, items}
    training: dict | None = None    # {weekly_volume, sessions, exercises: [...]}
    aesthetics: dict | None = None  # {skin: 80, oral: 90, ...}


class CoachChatOut(BaseModel):
    reply: str
    actions: list[dict] = []  # confirmable habit changes the coach proposed


class CoachContextIn(BaseModel):
    habits: list[dict] = []
    profile: dict | None = None
    diet: dict | None = None
    training: dict | None = None
    aesthetics: dict | None = None


class NutritionIn(BaseModel):
    description: str  # a food/meal, e.g. "2 eggs and a slice of toast"


class NutritionOut(BaseModel):
    calories: float
    protein: float
    carbs: float
    fat: float
    fibre: float
    micros: dict[str, float] = {}  # canonical keys (sodium_mg, vitamin_c_mg, …)
