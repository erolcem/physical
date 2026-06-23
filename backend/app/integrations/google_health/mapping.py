"""Google Health dataPoints → canonical samples.

Real dataPoint shape (confirmed live):
    {
      "dataSource": {...},                         # metadata
      "dailyRestingHeartRate": {                   # type-named value container
        "date": {"year": 2026, "month": 6, "day": 23},
        "beatsPerMinute": "49",                    # value — note: a STRING
        "dailyRestingHeartRateMetadata": {...}
      }
    }

So: the value lives in a type-named container; the date is a nested {year,month,day}
object; numeric values arrive as strings. `source_id` is stable per (metric, day)
so re-syncing is idempotent.
"""
SOURCE = "google_health"

# Top-level keys on a dataPoint that are metadata, not the value container.
_TOP_META = {"dataSource", "dataSourceFamily", "dataPointId", "originDataPointId",
             "createTime", "modifyTime", "dataType", "interval",
             "startTime", "endTime", "civilStartTime", "civilEndTime"}


def _to_float(v):
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str):
        try:
            return float(v)
        except ValueError:
            return None
    return None


def _container(point: dict) -> dict | None:
    """The type-named value object (e.g. 'dailyRestingHeartRate'), skipping
    metadata like 'dataSource'."""
    return next((v for k, v in point.items()
                 if k not in _TOP_META and isinstance(v, dict)), None)


def _day_of(container: dict) -> str | None:
    for v in container.values():  # the nested {year, month, day} date object
        if isinstance(v, dict) and v.get("year"):
            return f"{int(v['year']):04d}-{int(v['month']):02d}-{int(v['day']):02d}"
    iso = (container.get("interval") or {}).get("startTime") or container.get("startTime") or ""
    return iso[:10] or None


def _active_zone(container: dict):
    total, found = 0.0, False
    for k in ("sumInCardioHeartZone", "sumInPeakHeartZone", "sumInFatBurnHeartZone"):
        f = _to_float(container.get(k))
        if f is not None:
            total, found = total + f, True
    return total if found else None


def _first_value(container: dict):
    # First scalar (number or numeric string) that isn't the date or metadata.
    for k, v in container.items():
        if k == "date" or k.endswith("Metadata") or isinstance(v, dict):
            continue
        f = _to_float(v)
        if f is not None:
            return f
    return None


# Single-value metrics use the generic first-value extractor; active zone sums zones.
_EXTRACTORS = {"active_zone": _active_zone}


def to_samples(metric_id: str, datapoints: list[dict]) -> list[dict]:
    out = []
    for p in datapoints:
        container = _container(p)
        if container is None:
            continue
        day = _day_of(container)
        if not day:
            continue
        val = _EXTRACTORS.get(metric_id, _first_value)(container)
        if val is None:
            continue
        out.append({
            "metric_id": metric_id, "ts": f"{day}T00:00:00", "value": float(val),
            "source": SOURCE, "source_id": f"{metric_id}:{day}", "raw": container,
        })
    return out
