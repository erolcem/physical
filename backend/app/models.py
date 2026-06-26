"""ORM models for the canonical store (design doc §2.2 / §2.3)."""
import datetime as dt

from sqlalchemy import DateTime, Float, Index, Integer, JSON, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base


def _utcnow() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


class Sample(Base):
    """The one canonical time-series shape every source normalises into.

    `value` is the canonical number the rank engine reads (for strength that is
    the estimated 1RM in kg; `raw` keeps the original {weight, reps, unit}).
    `bodyweight_at_ts` is the immutable snapshot used to score strength lifts
    (bodyweight-at-time). Dedup is `(user, metric, source, source_id)` so a
    re-synced Fitbit day never double-counts.
    """
    __tablename__ = "samples"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String, index=True)
    metric_id: Mapped[str] = mapped_column(String, index=True)
    ts: Mapped[dt.datetime] = mapped_column(DateTime)
    value: Mapped[float] = mapped_column(Float)
    bodyweight_at_ts: Mapped[float | None] = mapped_column(Float, nullable=True)
    raw: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    source: Mapped[str] = mapped_column(String, default="manual")
    source_id: Mapped[str] = mapped_column(String)
    ingested_at: Mapped[dt.datetime] = mapped_column(DateTime, default=_utcnow)

    __table_args__ = (
        UniqueConstraint("user_id", "metric_id", "source", "source_id",
                         name="uq_sample_dedup"),
        Index("ix_user_metric_ts", "user_id", "metric_id", "ts"),
    )


class User(Base):
    """An account. `id` is the stable user id used everywhere as `user_id`
    (Google 'sub' for real sign-ins, or a chosen id for dev). All samples,
    profile, and Google tokens are keyed by this id → per-user isolation."""
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    email: Mapped[str | None] = mapped_column(String, nullable=True)
    name: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime, default=_utcnow)


class GoogleHealthToken(Base):
    """Per-user Google OAuth tokens for the Google Health API cloud adapter.
    Note: in OAuth 'testing' mode Google refresh tokens expire after 7 days."""
    __tablename__ = "google_health_tokens"

    user_id: Mapped[str] = mapped_column(String, primary_key=True)
    access_token: Mapped[str] = mapped_column(String)
    refresh_token: Mapped[str] = mapped_column(String)
    expires_at: Mapped[dt.datetime] = mapped_column(DateTime)
    scope: Mapped[str | None] = mapped_column(String, nullable=True)
