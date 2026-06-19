-- TimescaleDB setup. Run ONCE, AFTER the app has created its tables on first
-- start (Base.metadata.create_all):
--     psql "$DATABASE_URL" -f scripts/timescale_init.sql
--
-- TimescaleDB requires any UNIQUE/PRIMARY KEY to include the partitioning
-- column (ts). Our (user, metric, source, source_id) dedup is enforced at the
-- application layer (routers/samples.py), so we drop the DB-level unique
-- constraint, convert `samples` to a hypertable on `ts`, and keep a non-unique
-- index so the app's dedup lookup stays fast.
CREATE EXTENSION IF NOT EXISTS timescaledb;

ALTER TABLE samples DROP CONSTRAINT IF EXISTS uq_sample_dedup;

SELECT create_hypertable('samples', 'ts', if_not_exists => TRUE, migrate_data => TRUE);

CREATE INDEX IF NOT EXISTS ix_sample_dedup
  ON samples (user_id, metric_id, source, source_id);
