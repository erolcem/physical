"""Google Health dataPoints → canonical samples, with per-metric extractors
written against the real response shapes (confirmed via /debug).

Shapes vary: the date may be `container.date` (resting HR) or buried (weight:
`sampleTime.civilTime.date`); values may be strings; sleep is one rich record
per night that expands into several background metrics. `source_id` is stable
per (metric, day) so re-syncing is idempotent.
"""
SOURCE = "google_health"

_TOP_META = {"dataSource", "dataSourceFamily", "dataPointId", "originDataPointId",
             "createTime", "modifyTime", "dataType", "name",
             "civilStartTime", "civilEndTime"}


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
    metadata like 'dataSource' and the string 'name'."""
    return next((v for k, v in point.items()
                 if k not in _TOP_META and isinstance(v, dict)), None)


def _find_date(obj) -> str | None:
    """First {year, month, day} object found anywhere in the structure."""
    if isinstance(obj, dict):
        if {"year", "month", "day"} <= obj.keys():
            return f"{int(obj['year']):04d}-{int(obj['month']):02d}-{int(obj['day']):02d}"
        for v in obj.values():
            d = _find_date(v)
            if d:
                return d
    elif isinstance(obj, list):
        for v in obj:
            d = _find_date(v)
            if d:
                return d
    return None


def _sample(metric_id, day, value, raw):
    return {"metric_id": metric_id, "ts": f"{day}T00:00:00", "value": float(value),
            "source": SOURCE, "source_id": f"{metric_id}:{day}", "raw": raw}


# ── per-metric value extractors (operate on the type-named container) ──
def _hrv(c):
    # Prefer the real overnight RMSSD; the 'average' field is often 0 on Fitbit.
    return (_to_float(c.get("deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds"))
            or _to_float(c.get("averageHeartRateVariabilityMilliseconds")))


def _bodyweight(c):
    g = _to_float(c.get("weightGrams"))
    return g / 1000.0 if g is not None else None


_EXTRACTORS = {
    "resting_hr": lambda c: _to_float(c.get("beatsPerMinute")),
    "hrv": _hrv,
    "vo2max": lambda c: _to_float(c.get("vo2Max")),
    "bodyweight": _bodyweight,
    "body_fat_pct": lambda c: _to_float(c.get("percentage")),
}


def _sleep_samples(datapoints: list[dict]) -> list[dict]:
    """One night → sleep_duration (hrs), sleep_efficiency (%), deep/rem minutes."""
    out = []
    for p in datapoints:
        c = _container(p)
        if not c:
            continue
        summary = c.get("summary") or {}
        day = (((c.get("interval") or {}).get("startTime")) or "")[:10] or _find_date(c)
        if not day:
            continue
        asleep = _to_float(summary.get("minutesAsleep"))
        period = _to_float(summary.get("minutesInSleepPeriod"))
        if asleep is not None:
            out.append(_sample("sleep_duration", day, asleep / 60.0, summary))
        if asleep and period:
            out.append(_sample("sleep_efficiency", day, round(asleep / period * 100, 1), summary))
        for st in (summary.get("stagesSummary") or []):
            mins = _to_float(st.get("minutes"))
            if mins is None:
                continue
            if st.get("type") == "DEEP":
                out.append(_sample("deep_sleep", day, mins, st))
            elif st.get("type") == "REM":
                out.append(_sample("rem_sleep", day, mins, st))
    return out


def to_samples(metric_id: str, datapoints: list[dict]) -> list[dict]:
    if metric_id == "sleep":
        return _sleep_samples(datapoints)
    out = []
    for p in datapoints:
        container = _container(p)
        if container is None:
            continue
        day = _find_date(container)
        if not day:
            continue
        val = _EXTRACTORS.get(metric_id, lambda c: None)(container)
        if val is None:
            continue
        out.append(_sample(metric_id, day, val, container))
    return out
