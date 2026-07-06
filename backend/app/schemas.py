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
    habits: list[dict] = []  # rich: {title, section, target, unit, measured, met, streak, …}
    profile: dict | None = None
    diet: dict | None = None        # today's totals: {calories, protein, carbs, fat, items}
    training: dict | None = None    # {weekly_volume, sessions, exercises: [...]}
    aesthetics: dict | None = None  # {skin: 80, oral: 90, ...}
    # App-computed analytical context (the app is authoritative + holds the full data).
    ranks: dict | None = None       # {overall, categories:{}, metrics:[{id,label,tier,top_pct,value,trend}]}
    trends: dict | None = None      # {metric_id: {change, direction, recent:[..]}}
    correlations: list[dict] = []   # [{a, b, r, n}] strong day-aligned correlations
    workout_sets: list[dict] = []   # [{date, type, exercises:[{name, sets:[{w,r}], volume}]}]
    metric_history: dict | None = None  # {metric_id: [downsampled daily values, oldest→newest]}
    energy: dict | None = None      # {in:[daily kcal], out:[daily est kcal], bmr}
    meals: list[dict] = []          # last-7-days food entries [{d, n, kcal, p, fib?}]


class CoachChatOut(BaseModel):
    reply: str
    actions: list[dict] = []  # confirmable habit changes the coach proposed


class CoachContextIn(BaseModel):
    habits: list[dict] = []
    profile: dict | None = None
    diet: dict | None = None
    training: dict | None = None
    aesthetics: dict | None = None
    ranks: dict | None = None
    trends: dict | None = None
    correlations: list[dict] = []
    workout_sets: list[dict] = []
    metric_history: dict | None = None  # {metric_id: [daily values]} — summarised, not echoed
    energy: dict | None = None          # {in:[daily kcal], out:[daily est kcal], bmr}
    meals: list[dict] = []              # recent food entries [{d, n, kcal, p, fib?}]


class HabitVerifyIn(BaseModel):
    """The day's habits + evidence for LLM verification (see habit_check.py)."""
    day: str  # YYYY-MM-DD
    habits: list[dict] = []    # {id, title, section, verify, target, compare, unit, goalKey, time}
    workouts: list[dict] = []  # that day's sessions incl. sets [{name, w, r, s, d}]
    food: list[dict] = []      # that day's food entries {name, calories, protein, …}
    metrics: dict = {}         # that day's metric readings {metric_id: value}


class HabitVerifyOut(BaseModel):
    verdicts: list[dict]  # [{id, done, reason}] — one per submitted habit
    model: str | None = None


class NutritionIn(BaseModel):
    description: str  # a food/meal, e.g. "2 eggs and a slice of toast"


class NutritionOut(BaseModel):
    calories: float
    protein: float
    carbs: float
    fat: float
    fibre: float
    micros: dict[str, float] = {}  # canonical keys (sodium_mg, vitamin_c_mg, …)
    health: dict[str, float] = {}  # diet-health radar axis points (0–100 per food)
