"""Turns stored samples into ranks via the canonical engine.

Mirrors the client exactly: the latest sample per ranked metric is scored at its
own bodyweight-at-time; overall and per-category ranks are z-space blends
(engine.overall) over those latest values.
"""
from . import engine as E
from .registry import category_of


def latest_by_metric(samples):
    latest = {}
    for s in samples:
        cur = latest.get(s.metric_id)
        if cur is None or s.ts > cur.ts:
            latest[s.metric_id] = s
    return latest


def compute_ranks(samples):
    latest = latest_by_metric(samples)
    metrics: dict[str, dict] = {}
    logs_by_cat: dict[str, list] = {}
    all_logs: list = []

    for mid, s in latest.items():
        if mid not in E.STANDARDS:
            continue  # tracked / background metric — never ranked
        try:
            res = E.tier_of(mid, s.value, s.bodyweight_at_ts)
        except ValueError:
            # e.g. a strength sample missing its bodyweight snapshot — skip it.
            continue
        metrics[mid] = {
            "metric_id": mid, "value": s.value, "ts": s.ts,
            "tier": res["tier"], "sub": res["sub"], "top_pct": res["top_pct"],
            "percentile": res["percentile"], "rank_value": res["rank_value"],
        }
        log = E.Log(mid, s.value, s.bodyweight_at_ts)
        all_logs.append(log)
        cat = category_of(mid)
        if cat:
            logs_by_cat.setdefault(cat, []).append(log)

    overall = E.overall(all_logs)
    categories = {cat: E.overall(logs) for cat, logs in logs_by_cat.items()}
    return overall, categories, metrics
