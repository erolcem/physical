"""Pure Fitbit JSON → canonical sample mappers. No I/O, fully unit-tested.

Each mapper returns a list of canonical sample dicts ready for ingest:
    {metric_id, ts, value, source='fitbit', source_id, raw}

`source_id` is stable per (metric, day) so re-syncing a day is idempotent
(the canonical store dedups on user+metric+source+source_id).
"""

SOURCE = "fitbit"


def _sample(metric_id, ts, value, source_id, raw=None):
    return {
        "metric_id": metric_id, "ts": ts, "value": float(value),
        "source": SOURCE, "source_id": source_id, "raw": raw,
    }


def _midpoint_vo2(v):
    # Fitbit returns vo2Max as a number or a range string like "42-46".
    if isinstance(v, str) and "-" in v:
        lo, hi = v.split("-", 1)
        return (float(lo) + float(hi)) / 2
    return float(v)


def map_resting_hr(data):
    out = []
    for a in data.get("activities-heart", []):
        rhr = (a.get("value") or {}).get("restingHeartRate")
        d = a.get("dateTime")
        if rhr is not None and d:
            out.append(_sample("resting_hr", f"{d}T00:00:00", rhr,
                               f"resting_hr:{d}", {"restingHeartRate": rhr}))
    return out


def map_hrv(data):
    out = []
    for h in data.get("hrv", []):
        rmssd = (h.get("value") or {}).get("dailyRmssd")
        d = h.get("dateTime")
        if rmssd is not None and d:
            out.append(_sample("hrv", f"{d}T00:00:00", rmssd, f"hrv:{d}", h.get("value")))
    return out


def map_cardio_score(data):
    out = []
    for c in data.get("cardioScore", []):
        v = (c.get("value") or {}).get("vo2Max")
        d = c.get("dateTime")
        if v is not None and d:
            out.append(_sample("vo2max", f"{d}T00:00:00", _midpoint_vo2(v),
                               f"vo2max:{d}", {"vo2Max": v}))
    return out


def map_activity(data, date):
    # /1/user/-/activities/date/{date}.json → {"summary": {...}}
    s = data.get("summary") or {}
    out = []
    if s.get("steps") is not None:
        out.append(_sample("steps", f"{date}T00:00:00", s["steps"], f"steps:{date}",
                           {"steps": s["steps"]}))
    if s.get("caloriesOut") is not None:
        out.append(_sample("energy_burned", f"{date}T00:00:00", s["caloriesOut"],
                           f"energy_burned:{date}", {"caloriesOut": s["caloriesOut"]}))
    azm = s.get("activeZoneMinutes")
    if isinstance(azm, dict):  # newer API nests it
        azm = azm.get("activeZoneMinutes") or azm.get("totalMinutes")
    if azm is not None:
        out.append(_sample("active_zone", f"{date}T00:00:00", azm, f"active_zone:{date}",
                           {"activeZoneMinutes": azm}))
    return out


def map_weight(data):
    # /1/user/-/body/log/weight/... → {"weight": [{date, time, weight, fat, ...}]}
    out = []
    for w in data.get("weight", []):
        d = w.get("date")
        if not d:
            continue
        ts = f"{d}T{w.get('time', '00:00:00')}"
        if w.get("weight") is not None:
            out.append(_sample("bodyweight", ts, w["weight"], f"bodyweight:{d}", w))
        if w.get("fat") is not None:
            out.append(_sample("body_fat_pct", ts, w["fat"], f"body_fat_pct:{d}", w))
    return out


def map_sleep(data):
    # /1.2/user/-/sleep/date/{date}.json. Fitbit's 0–100 "sleep score" is NOT in
    # the public API, so we map efficiency + stage minutes as background metrics.
    out = []
    for s in data.get("sleep", []):
        d = s.get("dateOfSleep")
        if not d:
            continue
        if s.get("efficiency") is not None:
            out.append(_sample("sleep_efficiency", f"{d}T00:00:00", s["efficiency"],
                               f"sleep_efficiency:{d}", None))
        if s.get("minutesAsleep") is not None:
            out.append(_sample("sleep_duration", f"{d}T00:00:00", s["minutesAsleep"] / 60.0,
                               f"sleep_duration:{d}", None))
        stages = ((s.get("levels") or {}).get("summary")) or {}
        for stage, metric in (("deep", "deep_sleep"), ("rem", "rem_sleep")):
            mins = (stages.get(stage) or {}).get("minutes")
            if mins is not None:
                out.append(_sample(metric, f"{d}T00:00:00", mins, f"{metric}:{d}", None))
    return out
