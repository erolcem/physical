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

## Note on the shared engine
The backend and the Flutter client must agree, so `physical_rank_engine.py` is
the single source of truth and `lib/engine/rank_engine.dart` is its port. Keep
`app/registry.py` (metric→category) in sync with `lib/data/metrics.dart` until a
shared generated registry replaces it.
