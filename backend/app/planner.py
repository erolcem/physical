"""AI weekly habit-roster builder (owner review round 4 / PDF Part 4-5).

"Plan my week with AI": Gemini reads the user's full context (ranks, trends,
recovery, diet, training history, current habits) plus an optional emphasised
goal, and proposes a complete SCAFFOLDED roster — habits with sections, verify
modes, numeric targets, times, weekly days, and (for gym habits) the actual
workout plan (exercises + sets) the habit will carry. The app shows the
proposal as a review sheet; nothing is applied without the user's tap.

Prompt + defensive parser here (pure, unit-tested); the network call lives in
routers/coach.py.
"""
import json
import re

PLAN_PROMPT = (
    "Design my weekly habit roster. Using ONLY the USER DATA (ranks, weaknesses, "
    "recovery, diet, training history, current habits) and my stated goal, propose a "
    "complete, realistic weekly plan of 6-12 habits across sleep, exercise, diet, "
    "recovery, aesthetics and misc.\n"
    "Rules:\n"
    "1. Ground every number in the data: protein target from bodyweight, calorie "
    "target from the energy balance and goal, training volume from what I actually "
    "handle, bedtime from my real sleep schedule. Never invent numbers.\n"
    "2. Gym habits carry their WORKOUT PLAN: 3-8 exercises with sets, using weights "
    "near my recent logged sets (null when unknown). Split them across specific "
    "weekly days that respect recovery.\n"
    "3. Prioritise my weakest ranked areas; keep the total time budget sane.\n"
    "4. Prefer improving/replacing my existing habits over duplicating them.\n"
    "5. Habits marked RETIRED/archived are ones I deleted — treat them as history: "
    "learn from their lifetime adherence (what stuck vs what didn't), don't quietly "
    "re-propose one, and only revive one if the data clearly argues for it (say so "
    "in the summary).\n"
    "Respond with ONLY a JSON object, no prose, no markdown fences:\n"
    "{\"summary\": \"<2-3 sentences: the strategy and why>\", \"habits\": [\n"
    "  {\"title\": str, \"section\": \"sleep|exercise|diet|aesthetics|recovery|misc\", "
    "\"verify\": \"metric|workout|diet|manual\", \"metric\": str|null, "
    "\"description\": \"<one specific sentence on what exactly counts, so the AI "
    "verifier can't be fooled by an unrelated activity>\"|null, "
    "\"target\": number|null, \"compare\": \"gte|lte\", \"unit\": str, "
    "\"goalKey\": str|null, \"time\": \"HH:MM\"|null, \"durationMins\": int, "
    "\"cadence\": \"daily|weekly\", \"days\": [1-7 Mon-Sun, weekly only], "
    "\"plan\": {\"name\": str, \"type\": \"Weightlifting|Run|Walk|Cycle|Swim|Sport|Other\", "
    "\"sets\": [{\"name\": str, \"w\": kg|null, \"r\": reps|null}]} | null}\n"
    "]}"
)

_SECTIONS = {"sleep", "exercise", "diet", "aesthetics", "recovery", "misc"}
# rank_log: rank check-in habits — verified app-side by counting the day's
# manually-tested ranked-metric logs (the planner may propose one).
_VERIFY = {"metric", "workout", "diet", "manual", "rank_log"}
_TYPES = {"Weightlifting", "Run", "Walk", "Cycle", "Swim", "Sport", "Other"}
_TIME_RE = re.compile(r"^\d{1,2}:\d{2}$")


def _num(v):
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return None
    return float(v)


def _clean_set(s) -> dict | None:
    if not isinstance(s, dict):
        return None
    name = str(s.get("name", "")).strip()[:60]
    if not name:
        return None
    out: dict = {"name": name}
    w = _num(s.get("w"))
    if w is not None and 0 < w < 1000:
        out["w"] = round(w, 2)
    r = s.get("r")
    if isinstance(r, (int, float)) and not isinstance(r, bool) and 0 < int(r) <= 100:
        out["r"] = int(r)
    return out


def _clean_plan(p) -> dict | None:
    if not isinstance(p, dict):
        return None
    sets = [c for c in (_clean_set(s) for s in (p.get("sets") or [])[:30]) if c]
    if not sets:
        return None
    return {
        "name": str(p.get("name", "Workout")).strip()[:60] or "Workout",
        "type": p.get("type") if p.get("type") in _TYPES else "Weightlifting",
        "sets": sets,
    }


def _clean_habit(h) -> dict | None:
    if not isinstance(h, dict):
        return None
    title = str(h.get("title", "")).strip()[:60]
    if not title:
        return None
    section = h.get("section") if h.get("section") in _SECTIONS else "misc"
    out: dict = {"title": title, "section": section,
                 "verify": h.get("verify") if h.get("verify") in _VERIFY else "manual",
                 "compare": "lte" if h.get("compare") == "lte" else "gte",
                 "cadence": "weekly" if h.get("cadence") == "weekly" else "daily"}
    if isinstance(h.get("metric"), str) and h["metric"].strip():
        out["metric"] = h["metric"].strip()[:40]
    tgt = _num(h.get("target"))
    if tgt is not None:
        out["target"] = tgt
    if isinstance(h.get("unit"), str):
        out["unit"] = h["unit"].strip()[:12]
    if isinstance(h.get("goalKey"), str) and h["goalKey"].strip():
        out["goalKey"] = h["goalKey"].strip()[:60]
    if isinstance(h.get("description"), str) and h["description"].strip():
        out["description"] = h["description"].strip()[:200]
    if isinstance(h.get("time"), str) and _TIME_RE.match(h["time"]):
        out["time"] = h["time"]
    dur = h.get("durationMins")
    if isinstance(dur, (int, float)) and not isinstance(dur, bool) and 0 < int(dur) <= 480:
        out["durationMins"] = int(dur)
    days = [int(d) for d in (h.get("days") or [])
            if isinstance(d, (int, float)) and not isinstance(d, bool) and 1 <= int(d) <= 7]
    if out["cadence"] == "weekly" and days:
        out["days"] = sorted(set(days))
    elif out["cadence"] == "weekly":
        out["cadence"] = "daily"  # weekly with no days makes no sense
    plan = _clean_plan(h.get("plan"))
    if plan and section == "exercise":
        out["plan"] = plan
        out["verify"] = "workout"  # a planned workout is verified by doing it
    return out


def parse_plan(text: str) -> dict | None:
    """Model reply → {"summary": str, "habits": [clean habit dicts]} or None.
    Defensive: prose/fences tolerated, junk fields dropped, never raises."""
    if not text:
        return None
    m = re.search(r"\{.*\}", text, re.DOTALL)
    if not m:
        return None
    try:
        obj = json.loads(m.group(0))
    except Exception:
        return None
    if not isinstance(obj, dict):
        return None
    habits = [c for c in (_clean_habit(h) for h in (obj.get("habits") or [])[:14]) if c]
    if not habits:
        return None
    return {"summary": str(obj.get("summary", "")).strip()[:600], "habits": habits}
