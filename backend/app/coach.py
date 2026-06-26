"""AI coach (PDF Part 5) — context assembly, system prompt, and agentic-action
parsing. Pure helpers so they're unit-tested; the Gemini network call lives in the
router. Only metrics, ranks, and habits go to the model — never identifiers
(PII-scrubbed).
"""
import json
import re

from .ranking import compute_ranks

SYSTEM_PROMPT = (
    "You are Physical's AI coach: a sharp, encouraging strength-and-conditioning "
    "and health coach. Be concise and specific, and ground every claim in the "
    "USER DATA below — never invent numbers. Physical ranks each trainable metric "
    "against the general young-male population (tiers Wood→Bronze→Silver→Gold→"
    "Platinum→Diamond→Champion→Titan→Glory); help the user raise their honest ranks "
    "with concrete, achievable next steps and habit suggestions, prioritising their "
    "weakest areas.\n"
    "You are a coach, not a clinician: do not diagnose or give medical advice; for "
    "anything medical, add a brief note to consult a professional. If data is "
    "missing, say so and suggest logging or syncing it rather than guessing.\n\n"
    "When you recommend the user ADD or REMOVE a specific habit, append a fenced "
    "block so they can apply it in one tap (they always confirm). Use exactly:\n"
    "```action\n"
    '{"type": "add_habit", "title": "Mobility flow", "category": "performance", '
    '"durationMins": 10, "time": "07:00"}\n'
    "```\n"
    'or {"type": "remove_habit", "title": "<existing habit title>"}. category is one '
    "of sleep|exercise|diet|aesthetics|recovery|misc; include only the fields you "
    "mean; keep titles short. Propose at most one or two actions per reply, and only "
    "when clearly useful.\n"
    "Dynamic volume auto-regulation: if recovery markers (sleep score, HRV, resting "
    "heart rate) look poor, proactively propose easing the plan — remove or lighten a "
    "heavy training habit and/or add a short mobility/recovery one — via those actions.\n"
    "Strategic correlations: if you suspect two metrics move together (e.g. deep sleep "
    "and bench), pin it to their dashboard to watch with "
    '{"type": "pin_correlation", "a": "<metric_id>", "b": "<metric_id>"} — metric ids '
    "like sleep_score, hrv, resting_hr, vo2max, bench, squat, ohp, pullup, body_fat_pct."
)

_ACTION_RE = re.compile(r"```action\s*(\{.*?\})\s*```", re.DOTALL)
_ACTION_TYPES = {"add_habit", "remove_habit", "pin_correlation"}
_CATEGORIES = {"sleep", "exercise", "diet", "aesthetics", "recovery", "misc"}
_TIME_RE = re.compile(r"^\d{1,2}:\d{2}$")


def parse_actions(text: str):
    """Extract validated agentic actions from ```action blocks, returning
    (clean_text_without_blocks, actions). Malformed blocks are ignored — never
    raises. The app shows each action as a one-tap, user-confirmed Apply button."""
    actions = []
    for m in _ACTION_RE.finditer(text):
        try:
            obj = json.loads(m.group(1))
        except Exception:
            continue
        t = obj.get("type")
        if t not in _ACTION_TYPES:
            continue
        if t == "pin_correlation":
            a, b = str(obj.get("a", "")).strip(), str(obj.get("b", "")).strip()
            if a and b and a != b:
                actions.append({"type": t, "a": a, "b": b})
            continue
        title = str(obj.get("title", "")).strip()[:60]
        if not title:
            continue
        if t == "add_habit":
            act = {"type": t, "title": title,
                   "category": obj.get("category") if obj.get("category") in _CATEGORIES else "misc"}
            dur = obj.get("durationMins")
            if isinstance(dur, (int, float)) and not isinstance(dur, bool):
                act["durationMins"] = int(dur)
            tm = obj.get("time")
            if isinstance(tm, str) and _TIME_RE.match(tm):
                act["time"] = tm
            actions.append(act)
        else:  # remove_habit
            actions.append({"type": t, "title": title})
    clean = _ACTION_RE.sub("", text).strip()
    return clean, actions

# Metrics most useful to surface a recent value for, in context.
_RECENT = ["sleep_score", "hrv", "resting_hr", "vo2max", "body_fat_pct"]


def _fmt_rank(r) -> str:
    return f"{r['tier']} {r['sub']} (top {r['top_pct']:.0f}%)" if r else "unranked"


def _diet_line(diet) -> str | None:
    if not diet:
        return None
    cal, pro = diet.get("calories"), diet.get("protein")
    if not cal and not pro and not diet.get("items"):
        return None
    extra = ""
    if diet.get("carbs") or diet.get("fat"):
        extra = f", {int(diet.get('carbs') or 0)}g carbs, {int(diet.get('fat') or 0)}g fat"
    if diet.get("fibre"):
        extra += f", {int(diet['fibre'])}g fibre"
    micros = diet.get("micros") or {}
    mic = ", ".join(
        f"{k.rsplit('_', 1)[0].replace('_', ' ')} {int(v)}{'µg' if k.endswith('_ug') else 'mg'}"
        for k, v in micros.items() if v)
    tail = f"; micros: {mic}" if mic else ""
    return f"Today's diet: {int(cal or 0)} kcal, {int(pro or 0)}g protein{extra}{tail}"


def _training_line(training) -> str | None:
    if not training or not training.get("sessions"):
        return None
    ex = training.get("exercises") or []
    types = training.get("types") or []
    vol = int(training.get("weekly_volume") or 0)
    type_str = f" ({', '.join(types[:5])})" if types else ""
    tail = f"; exercises: {', '.join(ex[:8])}" if ex else ""
    return f"Training (last 7d): {int(training['sessions'])} sessions{type_str}, {vol} volume{tail}"


def _aesthetics_line(aesthetics) -> str | None:
    if not aesthetics:
        return None
    parts = [f"{k} {int(v)}" for k, v in aesthetics.items() if v is not None]
    return ("Aesthetics: " + ", ".join(parts)) if parts else None


def build_context(samples, habits=None, profile=None, diet=None, training=None,
                  aesthetics=None) -> str:
    """A compact, PII-free USER DATA block from canonical samples + app-supplied
    habits/profile/diet/training/aesthetics."""
    habits = habits or []
    lines: list[str] = []

    if profile:
        bits = []
        if profile.get("age"):
            bits.append(f"age {int(profile['age'])}")
        if profile.get("gender"):
            bits.append(str(profile["gender"]))
        if profile.get("heightCm"):
            bits.append(f"{float(profile['heightCm']):.0f}cm")
        if profile.get("weightKg"):
            bits.append(f"{float(profile['weightKg']):.0f}kg")
        if profile.get("bodyFatPct"):
            bits.append(f"{float(profile['bodyFatPct']):.0f}% body fat")
        if bits:
            lines.append("Profile: " + ", ".join(bits))

    if samples:
        overall, categories, metrics = compute_ranks(samples)
        lines.append(f"Overall rank: {_fmt_rank(overall)}")
        if categories:
            lines.append("Categories: "
                         + ", ".join(f"{c} {_fmt_rank(r)}" for c, r in categories.items()))
        ranked = sorted(metrics.items(), key=lambda kv: kv[1]["rank_value"])
        if ranked:
            w, s = ranked[0], ranked[-1]
            lines.append(f"Weakest: {w[0]} {_fmt_rank(w[1])}. "
                         f"Strongest: {s[0]} {_fmt_rank(s[1])}.")
        recent = [f"{m} {metrics[m]['value']:g}" for m in _RECENT if m in metrics]
        if recent:
            lines.append("Recent readings: " + ", ".join(recent))
    else:
        lines.append("No logged or synced data yet.")

    for line in (_diet_line(diet), _training_line(training), _aesthetics_line(aesthetics)):
        if line:
            lines.append(line)

    if habits:
        done = sum(1 for h in habits if h.get("done_today"))
        items = "; ".join(
            h.get("title", "?")
            + (f" [{h['category']}]" if h.get("category") else "")
            + (f", streak {int(h['streak'])}" if h.get("streak") else "")
            for h in habits[:12])
        lines.append(f"Habits ({done}/{len(habits)} done today): {items}")
    else:
        lines.append("No habits set yet.")

    return "\n".join(lines)


def compose_system(samples, habits=None, profile=None, diet=None, training=None,
                   aesthetics=None) -> str:
    ctx = build_context(samples, habits, profile, diet, training, aesthetics)
    return f"{SYSTEM_PROMPT}\n\n=== USER DATA ===\n{ctx}"


def context_sections(samples, habits=None, profile=None, diet=None, training=None,
                     aesthetics=None) -> dict:
    """The exact context the coach holds, as labelled sections — powers the
    transparency view so the user sees precisely what is (and isn't) shared."""
    habits = habits or []
    out = {
        "profile": None, "overall": None, "categories": {},
        "weakest": None, "strongest": None, "recent": {},
        "diet": _diet_line(diet), "training": _training_line(training),
        "aesthetics": _aesthetics_line(aesthetics), "habits": [],
        "note": ("Only this data is sent to your AI coach. Your email, name, and "
                 "account id are never shared."),
    }
    if profile:
        bits = []
        if profile.get("age"):
            bits.append(f"age {int(profile['age'])}")
        if profile.get("gender"):
            bits.append(str(profile["gender"]))
        if profile.get("heightCm"):
            bits.append(f"{float(profile['heightCm']):.0f}cm")
        if profile.get("weightKg"):
            bits.append(f"{float(profile['weightKg']):.0f}kg")
        if profile.get("bodyFatPct"):
            bits.append(f"{float(profile['bodyFatPct']):.0f}% body fat")
        out["profile"] = ", ".join(bits) or None
    if samples:
        overall, categories, metrics = compute_ranks(samples)
        out["overall"] = _fmt_rank(overall)
        out["categories"] = {c: _fmt_rank(r) for c, r in categories.items()}
        ranked = sorted(metrics.items(), key=lambda kv: kv[1]["rank_value"])
        if ranked:
            out["weakest"] = f"{ranked[0][0]} — {_fmt_rank(ranked[0][1])}"
            out["strongest"] = f"{ranked[-1][0]} — {_fmt_rank(ranked[-1][1])}"
        out["recent"] = {m: metrics[m]["value"] for m in _RECENT if m in metrics}
    out["habits"] = [
        h.get("title", "?")
        + (f" [{h['category']}]" if h.get("category") else "")
        + (f" · streak {int(h['streak'])}" if h.get("streak") else "")
        + (" · done today" if h.get("done_today") else "")
        for h in habits
    ]
    return out
