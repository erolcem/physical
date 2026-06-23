"""Google Health dataPoints → canonical samples.

`source_id` is stable per (metric, day) so re-syncing is idempotent. The exact
rollup field names are only partly documented publicly, so we use specific
extractors for the ones we know (sumSteps, the active-zone sums) and a tolerant
"first numeric value" fallback for single-value metrics (resting HR, HRV, VO₂max,
weight, body-fat). These are verified against the real response on first sync.
"""
SOURCE = "google_health"


def _first_number(value: dict):
    for v in (value or {}).values():
        if isinstance(v, bool):
            continue
        if isinstance(v, (int, float)):
            return float(v)
    return None


def _active_zone(value: dict):
    parts = [value.get("sumInCardioHeartZone"), value.get("sumInPeakHeartZone"),
             value.get("sumInFatBurnHeartZone")]
    nums = [p for p in parts if isinstance(p, (int, float))]
    return float(sum(nums)) if nums else None


# Known field extractors; everything else falls back to _first_number.
_EXTRACTORS = {
    "steps": lambda v: v.get("sumSteps"),
    "active_zone": _active_zone,
}


def to_samples(metric_id: str, datapoints: list[dict]) -> list[dict]:
    out = []
    for p in datapoints:
        day = (p.get("startTime") or p.get("date") or p.get("startDate") or "")[:10]
        value_obj = p.get("value") or p.get("rollupValue") or p.get("rollUpValue") or {}
        extract = _EXTRACTORS.get(metric_id, _first_number)
        val = extract(value_obj)
        if val is None or not day:
            continue
        out.append({
            "metric_id": metric_id, "ts": f"{day}T00:00:00", "value": float(val),
            "source": SOURCE, "source_id": f"{metric_id}:{day}", "raw": value_obj,
        })
    return out
