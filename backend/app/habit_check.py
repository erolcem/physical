"""LLM habit verification (owner review round 3, items 4 & 7).

Rule-based verification ("any workout that day ticks every workout habit") is
brittle: two exercise habits both tick off one session, and custom habits can't
be checked at all. Instead, the app sends the day's EVIDENCE (workout sessions
with their sets, food log, metric readings) plus the habit roster, and Gemini
judges each habit like a strict human coach would — with an explicit
evidence-exclusivity rule so one session can't satisfy two distinct habits.

Pure prompt-building + defensive parsing here (unit-tested); the network call
lives in routers/habits.py. Manual habits are never judged — they stay
user-ticked by design.
"""
import json
import re

VERIFY_PROMPT = (
    "You are a strict, honest habit verifier for a fitness app. You are given a "
    "date, the user's habit checklist, and ALL the objective evidence recorded "
    "that day (workout sessions with individual sets, food log, and metric "
    "readings such as sleep score / steps / heart-rate data).\n\n"
    "For EACH habit decide whether the evidence proves it was completed that day.\n"
    "Rules:\n"
    "1. EVIDENCE EXCLUSIVITY: one piece of evidence satisfies at most ONE habit. "
    "If two habits both claim the same kind of activity (e.g. 'Train' twice, or "
    "'Train' + 'Cardio session'), they need clearly distinct evidence (two separate "
    "sessions, or one lifting session and one run). Otherwise mark only the single "
    "best-matching habit done and the rest not done.\n"
    "2. TARGETS ARE BINDING: a habit with a numeric target (e.g. protein ≥ 150 g, "
    "steps ≥ 8000, calories ≤ 2200) is done only if the day's measured total "
    "actually satisfies it. Compute totals from the evidence.\n"
    "3. SEMANTIC MATCHING: match habits to evidence by meaning, not keywords — "
    "'Push day', 'Chest sets' and 'Bench 3×5' are lifting evidence; a 'Run 5.2 km' "
    "session is cardio evidence; a food entry is diet evidence. Custom habit titles "
    "must be interpreted sensibly.\n"
    "4. WHEN UNSURE, SAY NOT DONE: no benefit of the doubt — absence of evidence "
    "means not done. Never invent evidence.\n"
    "5. Time-of-day only matters when the habit clearly requires it (e.g. 'In bed "
    "by 23:00' uses the sleep-schedule reading).\n"
    "6. WATCH ANCHORING: each workout session carries watch_verified — true means "
    "it IS (or is linked to) a real tracked watch exercise; false means it's "
    "self-reported typing with no tracked exercise covering that window. Do NOT "
    "credit exercise habits from watch_verified=false sessions — typed sets alone "
    "prove nothing.\n\n"
    "Respond with ONLY a JSON object, no prose, no markdown fences:\n"
    "{\"verdicts\": [{\"id\": \"<habit id>\", \"done\": true|false, "
    "\"reason\": \"<max 12 words citing the evidence>\"}, ...]}\n"
    "Include every habit exactly once."
)


def build_evidence(day: str, habits: list[dict], workouts: list[dict],
                   food: list[dict], metrics: dict) -> str:
    """The user-turn payload: the roster + the day's evidence, compact JSON."""
    return json.dumps({
        "date": day,
        "habits": habits,
        "evidence": {
            "workout_sessions": workouts,
            "food_log": food,
            "metric_readings": metrics,
        },
    }, ensure_ascii=False)


def parse_verdicts(text: str, habit_ids: list[str]) -> list[dict]:
    """Extract verdicts from the model reply — only known habit ids, booleans
    coerced, reasons clipped. Missing habits default to not-done (rule 4).
    Never raises."""
    verdicts: dict[str, dict] = {}
    if text:
        m = re.search(r"\{.*\}", text, re.DOTALL)
        if m:
            try:
                obj = json.loads(m.group(0))
                rows = obj.get("verdicts") if isinstance(obj, dict) else None
                for r in (rows if isinstance(rows, list) else []):
                    if not isinstance(r, dict):
                        continue
                    hid = str(r.get("id", ""))
                    if hid not in habit_ids or hid in verdicts:
                        continue
                    verdicts[hid] = {
                        "id": hid,
                        "done": r.get("done") is True,
                        "reason": str(r.get("reason", ""))[:120],
                    }
            except Exception:
                pass
    return [verdicts.get(h, {"id": h, "done": False, "reason": "no verdict returned"})
            for h in habit_ids]
