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

**Auth:** every `/me/*` and `/integrations/*` route requires
`Authorization: Bearer <jwt>`; the user is read from the token (no path ids), so
a caller only ever touches their own data. Get a token via `/auth/google`
(production) or `/auth/dev` (local).

| Method | Path | Purpose |
|---|---|---|
| GET  | `/health` | Liveness + engine metric count (no auth) |
| POST | `/auth/dev` `{user_id}` | Local dev sign-in → `{access_token}` |
| POST | `/auth/google` `{id_token}` | Google Sign-In → `{access_token}` |
| GET  | `/auth/me` | Current user (auth) |
| PUT/GET | `/me/profile` | Upsert / fetch the signed-in user's profile |
| POST | `/me/samples` | Bulk-ingest canonical samples (idempotent) |
| GET  | `/me/samples?metric_id=&source=` | List samples |
| GET  | `/me/ranks` | Overall + per-category + per-metric ranks |

```bash
# Local: sign in, then call /me/* with the token.
TOKEN=$(curl -s -X POST localhost:8000/auth/dev -H 'Content-Type: application/json' \
        -d '{"user_id":"local-dev"}' | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")
curl -s localhost:8000/me/ranks -H "Authorization: Bearer $TOKEN"
```

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

**Connect & sync** (all calls carry your `$TOKEN` from the auth section above):
1. Get the consent URL and open it in a browser:
   `curl -s localhost:8000/integrations/google/authorize -H "Authorization: Bearer $TOKEN"`
   → `{"authorize_url": "..."}`. Approve; Google redirects to
   `https://www.google.com/?...&code=XXXX` — copy the `code`.
2. `curl -X POST "localhost:8000/integrations/google/exchange?code=XXXX" -H "Authorization: Bearer $TOKEN"`
   → stores your tokens.
3. `curl -X POST "localhost:8000/integrations/google/sync?days=7" -H "Authorization: Bearer $TOKEN"`
   → pulls and ingests. Then `GET /me/ranks` reflects the real data.
   (Add `&replace=true` to overwrite previously-ingested Google values.)

Mapped: resting HR, HRV (deep-sleep RMSSD), VO₂max, weight/body-fat, and sleep
(duration/efficiency/deep/REM). steps/active-zone/energy are deferred (per-minute
intraday). Re-syncing a day is idempotent (dedup on `source_id`). **Note:** in
OAuth testing mode Google refresh tokens expire after 7 days, so you re-authorize
weekly until the security review.

## Note on the shared engine
The backend and the Flutter client must agree, so `physical_rank_engine.py` is
the single source of truth and `lib/engine/rank_engine.dart` is its port. Keep
`app/registry.py` (metric→category) in sync with `lib/data/metrics.dart` until a
shared generated registry replaces it.
