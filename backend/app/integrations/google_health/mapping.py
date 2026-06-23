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

# Keys on a dataPoint that are metadata, not the value.
_META_KEYS = {"civilStartTime", "civilEndTime", "startTime", "endTime", "interval",
              "dataSource", "dataSourceFamily", "dataPointId", "originDataPointId",
              "createTime", "modifyTime", "dataType"}


def _day_of(point: dict) -> str | None:
    cst = point.get("civilStartTime")
    if cst and cst.get("year"):
        return f"{int(cst['year']):04d}-{int(cst['month']):02d}-{int(cst['day']):02d}"
    iso = (point.get("startTime") or point.get("date")
           or (point.get("interval") or {}).get("startTime") or "")
    return iso[:10] or None


def _value_object(point: dict) -> dict | None:
    # The value lives under a type-named key (steps/heartRate/weight/...). Prefer
    # the first non-metadata object; fall back to top-level numeric fields.
    obj = next((v for k, v in point.items()
                if k not in _META_KEYS and isinstance(v, dict)), None)
    if obj is not None:
        return obj
    nums = {k: v for k, v in point.items()
            if k not in _META_KEYS and isinstance(v, (int, float)) and not isinstance(v, bool)}
    return nums or None


def to_samples(metric_id: str, datapoints: list[dict]) -> list[dict]:
    out = []
    for p in datapoints:
        day = _day_of(p)
        value_obj = _value_object(p)
        if not day or value_obj is None:
            continue
        extract = _EXTRACTORS.get(metric_id, _first_number)
        val = extract(value_obj)
        if val is None:
            continue
        out.append({
            "metric_id": metric_id, "ts": f"{day}T00:00:00", "value": float(val),
            "source": SOURCE, "source_id": f"{metric_id}:{day}", "raw": value_obj,
        })
    return out
