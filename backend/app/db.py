"""SQLAlchemy engine/session wiring. DB-agnostic (SQLite dev, Postgres prod)."""
from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker
from sqlalchemy.pool import StaticPool

from .config import settings


class Base(DeclarativeBase):
    pass


_url = settings.database_url
_is_sqlite = _url.startswith("sqlite")
_is_memory = _url in ("sqlite://", "sqlite:///:memory:")
_connect_args = {"check_same_thread": False} if _is_sqlite else {}
# In-memory SQLite is per-connection; share one connection so the schema created
# at startup is visible to every request.
_kwargs = {"poolclass": StaticPool} if _is_memory else {}
engine = create_engine(_url, connect_args=_connect_args, future=True, **_kwargs)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


def get_db():
    """FastAPI dependency — yields a session, always closes it."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db() -> None:
    # Import models so they register on Base before create_all.
    from . import models  # noqa: F401
    Base.metadata.create_all(engine)
