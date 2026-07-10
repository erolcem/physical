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

    # Google Health API integration (register a project in Google Cloud Console;
    # the legacy Fitbit Web API is deprecated for new apps). The redirect URI must
    # match one registered on the OAuth client; Google's docs use https://www.google.com
    # for the manual code-paste flow that suits a local backend.
    google_client_id: str = os.environ.get("GOOGLE_CLIENT_ID", "")
    google_client_secret: str = os.environ.get("GOOGLE_CLIENT_SECRET", "")
    google_redirect_uri: str = os.environ.get(
        "GOOGLE_REDIRECT_URI", "https://www.google.com")

    # Auth. JWT_SECRET MUST be set to a strong random value in production.
    jwt_secret: str = os.environ.get("JWT_SECRET", "dev-insecure-secret-change-me-in-production-0123456789")
    jwt_expire_days: int = int(os.environ.get("JWT_EXPIRE_DAYS", "30"))
    # Dev-only password-less sign-in (/auth/dev). Disable in production.
    allow_dev_auth: bool = os.environ.get("ALLOW_DEV_AUTH", "true").lower() == "true"
    # CORS allowed origins (comma-separated). "*" is fine for native clients;
    # set to your app's web origin(s) for a web build.
    cors_origins: list[str] = os.environ.get("CORS_ORIGINS", "*").split(",")

    # Shown on the privacy policy / terms pages and used as the data-deletion
    # contact. Set CONTACT_EMAIL to your real address before any verification.
    contact_email: str = os.environ.get("CONTACT_EMAIL", "your-email@example.com")
    app_name: str = os.environ.get("APP_NAME", "Physical")

    # AI coach (PDF Part 5) — Gemini, to stay in the user's Google ecosystem.
    # Get a key from Google AI Studio (aistudio.google.com).
    # Two tiers: GEMINI_MODEL powers the correctness-critical, low-frequency calls
    # (coach chat, weekly planner, evening digest, habit verification — deep
    # reasoning over the full context; Pro-class); GEMINI_FAST_MODEL powers the
    # high-frequency, low-stakes calls (nutrition estimates, nudge lines,
    # food-health enrichment) where Flash is plenty and ~4-20× cheaper.
    # Defaults = the best GA model per tier as of July 2026: gemini-3.1-pro
    # ($2/$12 per 1M) and gemini-3-flash ($0.50/$3 — cheaper AND stronger than
    # the old 2.5-flash). The client degrades 404s to the fast model, so an id
    # that's unavailable for a key/region never breaks the app; override with
    # the env vars as new models ship.
    gemini_api_key: str = os.environ.get("GEMINI_API_KEY", "")
    gemini_model: str = os.environ.get("GEMINI_MODEL", "gemini-3.1-pro")
    gemini_fast_model: str = os.environ.get("GEMINI_FAST_MODEL", "gemini-3-flash")


settings = Settings()
