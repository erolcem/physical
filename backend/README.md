# Physical — Backend (canonical store + rank API)

FastAPI service implementing the design doc's **canonical sample store** and
**rank API**. It imports the shared rank engine
(`../lib/engine/physical_rank_engine.py`) directly — the same file the Flutter
app ports to Dart — so ranks computed here match the client exactly.

**This slice:** canonical schema (samples + profile), idempotent sync/ingest with
dedup, and overall / per-category / per-metric rank endpoints. Auth, the
HealthKit/Fitbit adapters, and the AI coach are later in Phase 3.

## Run (dev — SQLite, zero infra)

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload        # http://localhost:8000/docs
pytest -q                            # tests run on in-memory SQLite
```

## Run (production-like — Postgres + TimescaleDB)

```bash
docker compose up -d
export DATABASE_URL=postgresql+psycopg2://physical:physical@localhost:5432/physical
uvicorn app.main:app --reload                       # creates tables on first start
psql "$DATABASE_URL" -f scripts/timescale_init.sql  # convert samples → hypertable
```

The SQLAlchemy schema is DB-agnostic, so the same models run on both. The
Timescale step drops the DB-level unique constraint (dedup is enforced in the
app) so `samples` can become a hypertable on `ts`.

## API

| Method | Path | Purpose |
|---|---|---|
| GET  | `/health` | Liveness + engine metric count |
| PUT  | `/users/{uid}/profile` | Upsert profile (sex, age, height, units) |
| GET  | `/users/{uid}/profile` | Fetch profile |
| POST | `/users/{uid}/samples` | Bulk-ingest canonical samples (idempotent) |
| GET  | `/users/{uid}/samples?metric_id=` | List samples |
| GET  | `/users/{uid}/ranks` | Overall + per-category + per-metric ranks |

### Canonical sample
```jsonc
{
  "metric_id": "bench",
  "ts": "2026-06-01T08:00:00",
  "value": 100,                 // canonical; for strength = est 1RM (kg).
  "bodyweight_at_ts": 80,       // immutable snapshot for strength scoring
  "raw": {"weight": 100, "reps": 5},  // if value omitted, server estimates 1RM
  "source": "manual",           // manual | healthkit | fitbit | ...
  "source_id": "..."            // optional; enables idempotent re-sync (dedup)
}
```
Dedup key is `(user, metric, source, source_id)`. Manual logs without a
`source_id` get one generated (always inserted). Tracked/background metrics
(aesthetics, sleep sub-metrics, etc.) are stored but never ranked — they have no
engine standard.

## Google Health API integration (cloud adapter)

Pulls the full Fitbit/Pixel data range — including metrics HealthKit can't get
from Fitbit (HRV, VO₂max, resting HR, sleep) — server-side via the **Google Health
API** (the legacy Fitbit Web API is deprecated for new apps; full turndown Sep 2026).

**Prerequisites (one-time, your accounts):**
1. **Migrate your Fitbit account to a Google account** — support.google.com/fitbit
   (the data is only reachable via Google once migrated).
2. **Google Cloud Console** → create/select a project → **enable the Google Health API**.
3. **OAuth consent screen** → set it to **External**, **Testing** mode, and add your
   own Google email under **Test users**. Add the Google Health scopes
   (`…/auth/googlehealth.*.readonly`). *These scopes are "Restricted": testing mode
   works for your own account; a public/production launch needs a security review.*
4. **Credentials → Create OAuth client ID → Web application.** Add
   `https://www.google.com` as an **Authorized redirect URI**. Copy the **Client ID**
   and **Client Secret**.

```bash
export GOOGLE_CLIENT_ID=xxxxxx.apps.googleusercontent.com
export GOOGLE_CLIENT_SECRET=xxxxxxxxxxxxxxxxxxxx
uvicorn app.main:app --reload
```

**Connect & sync:**
1. Open `http://localhost:8000/integrations/google/authorize?user_id=local-dev` →
   approve. Google redirects to `https://www.google.com/?...&code=XXXX` — copy the
   `code` value from that URL.
2. `curl -X POST "http://localhost:8000/integrations/google/exchange?user_id=local-dev&code=XXXX"`
   → stores your tokens.
3. `curl -X POST "http://localhost:8000/integrations/google/sync?user_id=local-dev&days=7"`
   → pulls and ingests. Then `GET /users/local-dev/ranks` reflects the real data.

Mapped: resting HR, HRV, VO₂max, steps, active-zone minutes, energy burned,
weight, body-fat (sleep pending live-schema verification). Re-syncing a day is
idempotent (dedup on `source_id`). **Note:** in OAuth testing mode Google refresh
tokens expire after 7 days, so you re-authorize weekly until the security review.

## Note on the shared engine
The backend and the Flutter client must agree, so `physical_rank_engine.py` is
the single source of truth and `lib/engine/rank_engine.dart` is its port. Keep
`app/registry.py` (metric→category) in sync with `lib/data/metrics.dart` until a
shared generated registry replaces it.
