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
    # Match what the Google Health / Fitbit app SHOWS: the whole-night average RMSSD.
    # Deep-sleep-only RMSSD reads higher (deep sleep has higher HRV) — that mismatch is
    # why our value looked off. Fall back to deep-sleep RMSSD only when the average is the
    # known Fitbit-zero quirk, so we still get a number.
    avg = _to_float(c.get("averageHeartRateVariabilityMilliseconds"))
    if avg and avg > 0:
        return avg
    return _to_float(c.get("deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds"))


def _bodyweight(c):
    g = _to_float(c.get("weightGrams"))
    return g / 1000.0 if g is not None else None


def _height(c):
    """Height in cm. Confirmed via /debug: Google sends `heightMillimeters` (e.g.
    "1900" → 190 cm); other units handled defensively in case the shape varies."""
    mm = _to_float(c.get("heightMillimeters")) or _to_float(c.get("heightMm"))
    if mm is not None:
        return round(mm / 10.0, 1)
    m = _to_float(c.get("heightMeters"))
    if m is not None:
        return round(m * 100.0, 1)
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
    "spo2": lambda c: _to_float(c.get("averagePercentage")),  # daily-oxygen-saturation
    "steps": lambda c: _first(c, ("count", "steps", "stepCount", "totalSteps")),
    "active_zone": lambda c: _first(c, ("minutes", "activeZoneMinutes", "totalActiveZoneMinutes")),
    "energy_burned": lambda c: _first(c, ("energyKcal", "calories", "kilocalories", "kcal", "energy")),
}


def _sleep_score(container: dict, summary: dict, asleep_min, efficiency_pct,
                 deep_min, rem_min, resting_hr=None, baseline_rhr=None):
    """A 0–100 nightly sleep score, ranked as a recovery metric.

    Prefers the vendor's own score (Fitbit/Google expose a 0–100 sleep score) if
    it's anywhere in the payload; otherwise derives a transparent composite from
    the night's readings — duration vs an 8h target (50%), deep+REM composition
    (25%), and restoration from resting-HR (25%, efficiency as a fallback). Lands
    typical nights near the engine's population mean (~77)."""
    # 1) Real vendor score if present (any 0–100 field whose key mentions "score").
    for src in (summary, container):
        for k, v in (src or {}).items():
            if "score" in k.lower():
                f = _to_float(v)
                if f is not None and 0 < f <= 100:
                    return round(f, 1)
    # 2) Derived estimate — Fitbit's three pillars: duration (50%), composition
    # (deep+REM, 25%), restoration (25%). Restoration uses the night's RESTING HR
    # (lower = better recovery), personalised vs the user's rolling-average RHR when
    # available, else an absolute scale, else falling back to sleep efficiency.
    if not asleep_min:
        return None
    dur = min(asleep_min / 480.0, 1.0)                                  # vs 8h
    composition = min(((deep_min or 0) + (rem_min or 0)) / asleep_min / 0.40, 1.0)
    if resting_hr is not None and baseline_rhr:
        restoration = min(max(0.5 + (baseline_rhr - resting_hr) / 10.0, 0.0), 1.0)
    elif resting_hr is not None:
        restoration = min(max((68 - resting_hr) / 23.0, 0.0), 1.0)      # 45→1, 68→0
    else:
        restoration = min(max(((efficiency_pct or 0) / 100 - 0.75) / 0.20, 0.0), 1.0)
    return round(100 * (0.5 * dur + 0.25 * composition + 0.25 * restoration), 1)


def _sleep_day(c: dict) -> str | None:
    """The night's local WAKE day — endTime adjusted by its UTC offset — matching
    how Fitbit attributes sleep (dateOfSleep = the morning you woke up). Wake-day
    attribution is what lets a pre-midnight main sleep (23:00→05:00) and a
    post-midnight back-to-sleep (06:30→08:00) aggregate onto the SAME day;
    start-day attribution split them across two days, so 'today' only ever
    showed the morning fragment. Falls back to the start time when no end is
    present."""
    interval = c.get("interval") or {}
    for tkey, offkey in (("endTime", "endUtcOffset"), ("startTime", "startUtcOffset")):
        t = interval.get(tkey)
        if not isinstance(t, str):
            continue
        try:
            d = datetime.fromisoformat(t.replace("Z", "+00:00"))
            off = str(interval.get(offkey, "0s")).rstrip("s")
            local = d + timedelta(seconds=int(off or 0))
            return f"{local.year:04d}-{local.month:02d}-{local.day:02d}"
        except Exception:
            return t[:10]
    return _find_date(c)


def _local_hour(interval: dict):
    """Local bedtime as a decimal hour on a MONOTONIC evening scale: 22.5 = 10:30pm,
    and post-midnight bedtimes continue past 24 (00:30 → 24.5, 01:54 → 25.9).
    Bedtime is circular; on a plain 0–24 scale a 00:30 bedtime reads as 0.5 and
    PASSES an "in bed by ≤ 23:00" target despite being the latest bedtime of all.
    The wrap point is noon: hours before 12:00 belong to the previous evening."""
    start = interval.get("startTime")
    if not isinstance(start, str):
        return None
    try:
        dt = datetime.fromisoformat(start.replace("Z", "+00:00"))
        off = int(str(interval.get("startUtcOffset", "0s")).rstrip("s") or 0)
        local = dt + timedelta(seconds=off)
        hour = round(local.hour + local.minute / 60.0, 2)
        return hour + 24 if hour < 12 else hour
    except Exception:
        return None


def _deep_latency(c: dict):
    """Minutes from the sleep period's start to the FIRST DEEP stage — the literal
    "time to sound sleep". Fitbit reports summary.minutesToFallAsleep as a flat 0
    through this API, so the stage timeline is the only honest source."""
    start = (c.get("interval") or {}).get("startTime")
    if not isinstance(start, str):
        return None
    deep_starts = []
    for s in (c.get("stages") or []):
        if s.get("type") != "DEEP" or not isinstance(s.get("startTime"), str):
            continue
        try:
            deep_starts.append(datetime.fromisoformat(s["startTime"].replace("Z", "+00:00")))
        except Exception:
            pass
    if not deep_starts:
        return None
    try:
        t0 = datetime.fromisoformat(start.replace("Z", "+00:00"))
    except Exception:
        return None
    mins = (min(deep_starts) - t0).total_seconds() / 60.0
    return round(mins, 1) if mins >= 0 else None


def _count_long_awake(stages: list, min_secs: int) -> int:
    """Number of AWAKE blocks lasting ≥ [min_secs] — a 'full awakening' vs a micro one."""
    n = 0
    for s in stages:
        if s.get("type") != "AWAKE":
            continue
        a, b = s.get("startTime"), s.get("endTime")
        if not (isinstance(a, str) and isinstance(b, str)):
            continue
        try:
            ad = datetime.fromisoformat(a.replace("Z", "+00:00"))
            bd = datetime.fromisoformat(b.replace("Z", "+00:00"))
            if (bd - ad).total_seconds() >= min_secs:
                n += 1
        except Exception:
            pass
    return n


def _sleep_samples(datapoints: list[dict], rhr_by_day=None, baseline_rhr=None) -> list[dict]:
    """Sleep records → ONE sample set per local day. A night broken by a full
    wake-up (or a nap) arrives as SEVERAL records for the same day — Fitbit splits
    them — and emitting one set per record used to mean the per-day dedupe kept
    only the FIRST segment ("it only adopted the partially complete data"). All of
    a day's records are AGGREGATED first: minutes (asleep/deep/REM/interruptions/
    awakenings) sum, efficiency = Σasleep/Σin-bed, bedtime + time-to-fall-asleep
    come from the MAIN (longest) record, and the score prefers the vendor's number
    for a single-record night but is derived from the aggregated totals when the
    night was split (the vendor score only covers the main segment).
    [rhr_by_day]/[baseline_rhr] feed the score's resting-HR restoration term.
    (restlessness + sound-sleep aren't exposed by the API — proprietary.)"""
    rhr_by_day = rhr_by_day or {}
    by_day: dict[str, list[dict]] = {}
    for p in datapoints:
        c = _container(p)
        if not c:
            continue
        day = _sleep_day(c)
        if day:
            by_day.setdefault(day, []).append(c)

    out = []
    for day, records in by_day.items():
        # The main record = the one with the most sleep (anchors bedtime/ttfa/score).
        def _asleep(c):
            return _to_float((c.get("summary") or {}).get("minutesAsleep")) or 0.0
        records.sort(key=_asleep, reverse=True)
        main = records[0]
        main_summary = main.get("summary") or {}

        asleep_total = period_total = deep_total = rem_total = 0.0
        interruptions = awakenings = 0.0
        saw_asleep = saw_period = saw_deep = saw_rem = saw_int = False
        for c in records:
            summary = c.get("summary") or {}
            a = _to_float(summary.get("minutesAsleep"))
            if a is not None:
                asleep_total += a
                saw_asleep = True
            pmin = _to_float(summary.get("minutesInSleepPeriod"))
            if pmin is not None:
                period_total += pmin
                saw_period = True
            for st in (summary.get("stagesSummary") or []):
                mins = _to_float(st.get("minutes"))
                if st.get("type") == "DEEP" and mins is not None:
                    deep_total += mins
                    saw_deep = True
                elif st.get("type") == "REM" and mins is not None:
                    rem_total += mins
                    saw_rem = True
                elif st.get("type") == "AWAKE":
                    cnt = _to_float(st.get("count"))
                    if cnt is not None:
                        interruptions += cnt
                        saw_int = True
            awakenings += _count_long_awake(c.get("stages") or [], 300)

        eff = None
        if saw_asleep:
            out.append(_sample("sleep_duration", day, asleep_total / 60.0,
                               {"records": len(records)}))
        if saw_asleep and saw_period and period_total > 0:
            eff = round(asleep_total / period_total * 100, 1)
            out.append(_sample("sleep_efficiency", day, eff, {"records": len(records)}))
        # "Time to sound sleep": bedtime → first DEEP stage (stage timeline).
        # minutesToFallAsleep is only trusted when nonzero — Fitbit sends a flat
        # 0 through this API, and logging that 0 forever was worse than nothing.
        ttfa = _deep_latency(main)
        if ttfa is None:
            mtfa = _to_float(main_summary.get("minutesToFallAsleep"))
            ttfa = mtfa if mtfa else None
        if ttfa is not None:
            out.append(_sample("time_to_sleep", day, ttfa, main_summary))
        if saw_deep:
            out.append(_sample("deep_sleep", day, deep_total, {"records": len(records)}))
        if saw_rem:
            out.append(_sample("rem_sleep", day, rem_total, {"records": len(records)}))
        if saw_int:
            out.append(_sample("sleep_interruptions", day, interruptions,
                               {"records": len(records)}))
        sched = _local_hour(main.get("interval") or {})
        if sched is not None:
            out.append(_sample("sleep_schedule", day, sched, main.get("interval") or {}))
        out.append(_sample("full_awakenings", day, awakenings, {"min_seconds": 300}))
        score = _sleep_score(
            main if len(records) == 1 else {},          # vendor score: single record only
            main_summary if len(records) == 1 else {},
            asleep_total if saw_asleep else None, eff,
            deep_total if saw_deep else None, rem_total if saw_rem else None,
            resting_hr=rhr_by_day.get(day), baseline_rhr=baseline_rhr)
        if score is not None:
            out.append(_sample("sleep_score", day, score, {"records": len(records)}))
    return out


# Google exercise types → our locked session types.
_EX_TYPE_MAP = {
    "WALKING": "Walk", "HIKING": "Walk", "RUNNING": "Run", "TREADMILL": "Run",
    "BIKING": "Cycle", "OUTDOOR_BIKE": "Cycle", "MOUNTAIN_BIKING": "Cycle",
    "SWIMMING": "Swim", "WEIGHTS": "Weightlifting", "WEIGHTLIFTING": "Weightlifting",
}


def _secs(v):
    if v is None:
        return None
    try:
        return int(str(v).rstrip("s"))
    except (TypeError, ValueError):
        return None


def _local_start(interval: dict):
    """interval.startTime (UTC) shifted by startUtcOffset → local 'YYYY-MM-DDTHH:MM:SS'."""
    start = interval.get("startTime")
    if not isinstance(start, str):
        return None
    try:
        d = datetime.fromisoformat(start.replace("Z", "+00:00"))
        off = int(str(interval.get("startUtcOffset", "0s")).rstrip("s") or 0)
        return (d + timedelta(seconds=off)).strftime("%Y-%m-%dT%H:%M:%S")
    except Exception:
        return start[:19]


def parse_nutrition_log(datapoints: list[dict]) -> list[dict]:
    """Google `nutrition-log` dataPoints → food dicts the app imports as FoodEntries
    (name, day, calories + macros). Only the RELIABLE energy + macros are taken: this
    source reports per-nutrient values under a `grams` key with inconsistent scaling
    (sodium looks like mg, potassium absurdly small), so micros are skipped — the app's
    AI pass handles micros/health for foods that need them."""
    out = []
    for p in datapoints:
        c = p.get("nutritionLog")
        if not isinstance(c, dict):
            continue
        interval = c.get("interval") or {}
        start = _local_start(interval)
        day = start[:10] if start else None
        if not day:
            civ = (interval.get("civilStartTime") or {}).get("date") or {}
            if civ.get("year"):
                day = f"{int(civ['year']):04d}-{int(civ.get('month', 1)):02d}-{int(civ.get('day', 1)):02d}"
        if not day:
            continue
        protein = fibre = 0.0
        for n in (c.get("nutrients") or []):
            g = _to_float((n.get("quantity") or {}).get("grams"))
            if g is None:
                continue
            if n.get("nutrient") == "PROTEIN":
                protein = g
            elif n.get("nutrient") == "DIETARY_FIBER":
                fibre = g
        gid = str(p.get("name") or "").rsplit("/", 1)[-1]
        out.append({
            "google_id": gid or f"{day}:{c.get('foodDisplayName', 'food')}",
            "name": c.get("foodDisplayName") or "Food",
            "day": day,
            "calories": _to_float((c.get("energy") or {}).get("kcal")) or 0.0,
            "protein": round(protein, 1),
            "carbs": _to_float((c.get("totalCarbohydrate") or {}).get("grams")) or 0.0,
            "fat": _to_float((c.get("totalFat") or {}).get("grams")) or 0.0,
            "fibre": round(fibre, 2),
            "meal_type": c.get("mealType"),
        })
    return out


def parse_exercise_sessions(datapoints: list[dict]) -> list[dict]:
    """Google `exercise` dataPoints → session dicts the app imports as WorkoutSessions
    (type, duration, and a cardio summary: calories/distance/steps/avg-HR/zone-minutes)."""
    out = []
    for p in datapoints:
        c = p.get("exercise")
        if not isinstance(c, dict):
            continue
        ms = c.get("metricsSummary") or {}
        zones = ms.get("heartRateZoneDurations") or {}
        active = sum((_secs(zones.get(k)) or 0)
                     for k in ("moderateTime", "vigorousTime", "peakTime"))
        dur = _secs(c.get("activeDuration"))
        dist_mm = _to_float(ms.get("distanceMillimeters"))
        ex_type = c.get("exerciseType") or ""
        out.append({
            "google_id": (p.get("name") or "").rsplit("/", 1)[-1] or None,
            "type": _EX_TYPE_MAP.get(ex_type, "Other"),
            "exercise_type": ex_type,
            "display_name": c.get("displayName") or ex_type.title().replace("_", " ") or None,
            "start": _local_start(c.get("interval") or {}),
            "duration_mins": round(dur / 60) if dur else None,
            "calories": _to_float(ms.get("caloriesKcal")),
            "distance_km": round(dist_mm / 1_000_000, 2) if dist_mm else None,
            "steps": _to_float(ms.get("steps")),
            "avg_hr": _to_float(ms.get("averageHeartRateBeatsPerMinute")),
            "zone_minutes": round(active / 60) if active else None,
            "cardio_load": _cardio_load(zones),
        })
    return out


def _cardio_load(zones: dict):
    """Edwards' TRIMP cardio load from heart-rate zone durations: Σ minutes-in-zone ×
    zone weight (light 1, fat-burn/moderate 2, cardio/vigorous 3, peak 4). Google's
    own cardio-load is proprietary and not exposed, so we reconstruct it per session."""
    weights = {"lightTime": 1, "moderateTime": 2, "vigorousTime": 3, "peakTime": 4}
    load = sum((_secs(zones.get(k)) or 0) / 60.0 * w for k, w in weights.items())
    return round(load) if load > 0 else None


def parse_intraday_daily(metric_id: str, datapoints: list[dict],
                         container_key: str, value_key: str, agg: str = "sum",
                         drop_oldest: bool = False) -> list[dict]:
    """Roll a continuous type's per-interval values into one value per day — `sum`
    (steps, active-zone-minutes) or `avg` (heart-rate). The list endpoint takes no time
    filter, so with [drop_oldest] the earliest day in the batch (whose intervals are cut
    off by the page window, under-counting the total) is discarded; today stays — it's a
    live running count that later syncs update via the ingest upsert.
    Day comes from interval.civilStartTime / interval.startTime, or sampleTime (HR)."""
    sums: dict[str, float] = {}
    counts: dict[str, int] = {}
    seen_ids: set[str] = set()
    for p in datapoints:
        pid = p.get("dataPointId") or p.get("name")
        if pid:  # paginated fetches can overlap — never double-count an interval
            if pid in seen_ids:
                continue
            seen_ids.add(pid)
        c = p.get(container_key) or {}
        interval = c.get("interval") or {}
        sample_time = c.get("sampleTime") or {}
        civ = interval.get("civilStartTime") or sample_time.get("civilTime") or {}
        date = civ.get("date")
        if date and {"year", "month", "day"} <= date.keys():
            day = f"{int(date['year']):04d}-{int(date['month']):02d}-{int(date['day']):02d}"
        else:
            t = interval.get("startTime") or sample_time.get("physicalTime") or ""
            day = t[:10] if len(t) >= 10 else None
        v = _to_float(c.get(value_key))
        if day and v is not None:
            sums[day] = sums.get(day, 0.0) + v
            counts[day] = counts.get(day, 0) + 1
    if drop_oldest and len(sums) > 1:
        sums.pop(min(sums.keys()))
    out = []
    for d, total in sums.items():
        val = (total / counts[d]) if agg == "avg" else total
        out.append(_sample(metric_id, d, round(val, 1), {"intraday": agg}))
    return out


def to_samples(metric_id: str, datapoints: list[dict], rhr_by_day=None, baseline_rhr=None) -> list[dict]:
    if metric_id == "sleep":
        return _sleep_samples(datapoints, rhr_by_day=rhr_by_day, baseline_rhr=baseline_rhr)
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
