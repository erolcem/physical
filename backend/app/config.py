"""Configuration. DATABASE_URL drives the datastore:

  • dev / tests  → sqlite (default; zero infra)
  • production   → postgresql+psycopg2://...  (Postgres + TimescaleDB; see
                   docker-compose.yml and scripts/timescale_init.sql)

The schema is SQLAlchemy and DB-agnostic, so the same models run on both.
"""
import os


class Settings:
    database_url: str = os.environ.get("DATABASE_URL", "sqlite:///./physical.db")
    # Allometric/standard config lives in the rank engine itself; nothing here.


settings = Settings()
