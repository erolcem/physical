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
    "3. SEMANTIC MATCHING — and be SPECIFIC, not generic: match habits to evidence "
    "by meaning, not keywords. A habit names a PARTICULAR activity; a different "
    "activity of the same broad category does NOT satisfy it. E.g. a habit 'Makiwara "
    "punching (evening)' is NOT completed by a 'Walk' session — different activity. "
    "'Push day', 'Chest sets' and 'Bench 3×5' are lifting evidence; a 'Run 5.2 km' "
    "session is running/cardio evidence; a food entry is diet evidence. Custom habit "
    "titles must be interpreted sensibly and STRICTLY.\n"
    "4. HONOUR THE DESCRIPTION: when a habit carries a `description`, it is the "
    "user's own definition of what counts (specific activity, intensity, time of "
    "day). Treat it as binding — evidence that doesn't match the description is NOT "
    "the habit, even if the title alone might loosely fit.\n"
    "5. WHEN UNSURE, SAY NOT DONE: no benefit of the doubt — absence of MATCHING "
    "evidence means not done. Never invent evidence, and never stretch an unrelated "
    "session to fit.\n"
    "6. TIME-OF-DAY: honour it whenever the habit or its description specifies one "
    "(e.g. 'Evening cardio', 'In bed by 23:00', 'Morning run') — an activity at the "
    "wrong time of day does not satisfy a time-specific habit. Session start times "
    "are in the evidence.\n"
    "7. MEAL IDENTITY: food entries carry an eaten-at `time` (HH:MM) and sometimes a "
    "`meal_type`. A habit naming a specific meal or eating window ('Dinner', 'Eat "
    "breakfast', 'Protein with lunch', 'No food after 21:00') is done ONLY if a food "
    "entry actually matches that meal: by meal_type when present, else by time "
    "(breakfast ≈ 04:00-11:00, lunch ≈ 11:00-16:00, dinner ≈ 16:30-23:00). A "
    "breakfast entry NEVER satisfies a dinner habit. A food entry with no time can "
    "satisfy only generic eating habits ('Log all meals'), not meal-specific ones. "
    "For 'no eating after HH:MM'-style habits, mark done only when every logged "
    "entry respects the cutoff AND at least one entry exists that day.\n"
    "8. WATCH ANCHORING: each workout session carries watch_verified — true means "
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
