"""Google Health dataPoints → canonical samples, with per-metric extractors
written against the real response shapes (confirmed via /debug).

Shapes vary: the date may be `container.date` (resting HR) or buried (weight:
`sampleTime.civilTime.date`); values may be strings; sleep is one rich record
per night that expands into several background metrics. `source_id` is stable
per (metric, day) so re-syncing is idempotent.
"""
from datetime import datetime, timedelta

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


def _height(c):
    """Height in cm from whatever unit Google uses (shape confirmed via /debug)."""
    m = _to_float(c.get("heightMeters"))
    if m is not None:
        return round(m * 100.0, 1)
    mm = _to_float(c.get("heightMm")) or _to_float(c.get("heightMillimeters"))
    if mm is not None:
        return round(mm / 10.0, 1)
    return _to_float(c.get("heightCm")) or _to_float(c.get("heightCentimeters"))


def _first(c, keys):
    """First present numeric among candidate field names (shapes vary by type)."""
    for k in keys:
        v = _to_float(c.get(k))
        if v is not None:
            return v
    return None


_EXTRACTORS = {
    "resting_hr": lambda c: _to_float(c.get("beatsPerMinute")),
    "hrv": _hrv,
    "vo2max": lambda c: _to_float(c.get("vo2Max")),
    "bodyweight": _bodyweight,
    "body_fat_pct": lambda c: _to_float(c.get("percentage")),
    "height": _height,
    # Background context (AI tier). Field names are best-effort across candidates;
    # confirm against /debug if a daily type lands empty.
    "steps": lambda c: _first(c, ("count", "steps", "stepCount", "totalSteps")),
    "active_zone": lambda c: _first(c, ("minutes", "activeZoneMinutes", "totalActiveZoneMinutes")),
    "energy_burned": lambda c: _first(c, ("energyKcal", "calories", "kilocalories", "kcal", "energy")),
}


def _sleep_score(container: dict, summary: dict, asleep_min, efficiency_pct,
                 deep_min, rem_min):
    """A 0–100 nightly sleep score, ranked as a recovery metric.

    Prefers the vendor's own score (Fitbit/Google expose a 0–100 sleep score) if
    it's anywhere in the payload; otherwise derives a transparent composite from
    the night's readings — duration vs an 8h target (50%), efficiency (25%), and
    restorative deep+REM share (25%). Lands typical nights near the engine's
    population mean (~77)."""
    # 1) Real vendor score if present (any 0–100 field whose key mentions "score").
    for src in (summary, container):
        for k, v in (src or {}).items():
            if "score" in k.lower():
                f = _to_float(v)
                if f is not None and 0 < f <= 100:
                    return round(f, 1)
    # 2) Derived estimate.
    if not asleep_min:
        return None
    dur = min(asleep_min / 480.0, 1.0)                                  # vs 8h
    eff = min(max(((efficiency_pct or 0) / 100 - 0.75) / 0.20, 0.0), 1.0)  # 75%→0, 95%→1
    restorative = ((deep_min or 0) + (rem_min or 0)) / asleep_min
    comp = min(restorative / 0.40, 1.0)                                 # ~40% deep+REM ideal
    return round(100 * (0.5 * dur + 0.25 * eff + 0.25 * comp), 1)


def _sleep_day(c: dict) -> str | None:
    """The night's LOCAL calendar day — startTime adjusted by its UTC offset — so a
    night beginning late local-evening is attributed to the right day (the raw
    startTime is UTC, e.g. 2026-06-24T15:54Z + 10h = the 25th locally)."""
    interval = c.get("interval") or {}
    start = interval.get("startTime")
    if not isinstance(start, str):
        return _find_date(c)
    try:
        dt = datetime.fromisoformat(start.replace("Z", "+00:00"))
        off = str(interval.get("startUtcOffset", "0s")).rstrip("s")
        local = dt + timedelta(seconds=int(off or 0))
        return f"{local.year:04d}-{local.month:02d}-{local.day:02d}"
    except Exception:
        return start[:10]


def _sleep_samples(datapoints: list[dict]) -> list[dict]:
    """One night → sleep_score (0–100, ranked) + sleep_duration (hrs),
    sleep_efficiency (%), deep/rem minutes, time-to-sleep, and full awakenings."""
    out = []
    for p in datapoints:
        c = _container(p)
        if not c:
            continue
        summary = c.get("summary") or {}
        day = _sleep_day(c)
        if not day:
            continue
        asleep = _to_float(summary.get("minutesAsleep"))
        period = _to_float(summary.get("minutesInSleepPeriod"))
        deep = rem = eff = None
        if asleep is not None:
            out.append(_sample("sleep_duration", day, asleep / 60.0, summary))
        if asleep and period:
            eff = round(asleep / period * 100, 1)
            out.append(_sample("sleep_efficiency", day, eff, summary))
        ttfa = _to_float(summary.get("minutesToFallAsleep"))
        if ttfa is not None:
            out.append(_sample("time_to_sleep", day, ttfa, summary))
        for st in (summary.get("stagesSummary") or []):
            t = st.get("type")
            mins = _to_float(st.get("minutes"))
            if t == "DEEP" and mins is not None:
                deep = mins
                out.append(_sample("deep_sleep", day, mins, st))
            elif t == "REM" and mins is not None:
                rem = mins
                out.append(_sample("rem_sleep", day, mins, st))
            elif t == "AWAKE":
                cnt = _to_float(st.get("count"))
                if cnt is not None:
                    out.append(_sample("full_awakenings", day, cnt, st))
        score = _sleep_score(c, summary, asleep, eff, deep, rem)
        if score is not None:
            out.append(_sample("sleep_score", day, score, summary))
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
