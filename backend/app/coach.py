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
    "of strength|performance|sleep|diet|aesthetics|other; include only the fields you "
    "mean; keep titles short. Propose at most one or two actions per reply, and only "
    "when clearly useful.\n"
    "Dynamic volume auto-regulation: if recovery markers (sleep score, HRV, resting "
    "heart rate) look poor, proactively propose easing the plan — remove or lighten a "
    "heavy training habit and/or add a short mobility/recovery one — via those actions."
)

_ACTION_RE = re.compile(r"```action\s*(\{.*?\})\s*```", re.DOTALL)
_ACTION_TYPES = {"add_habit", "remove_habit"}
_CATEGORIES = {"strength", "performance", "sleep", "diet", "aesthetics", "other"}
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
        title = str(obj.get("title", "")).strip()[:60]
        if t not in _ACTION_TYPES or not title:
            continue
        if t == "add_habit":
            a = {"type": t, "title": title,
                 "category": obj.get("category") if obj.get("category") in _CATEGORIES else "other"}
            dur = obj.get("durationMins")
            if isinstance(dur, (int, float)) and not isinstance(dur, bool):
                a["durationMins"] = int(dur)
            tm = obj.get("time")
            if isinstance(tm, str) and _TIME_RE.match(tm):
                a["time"] = tm
            actions.append(a)
        else:
            actions.append({"type": t, "title": title})
    clean = _ACTION_RE.sub("", text).strip()
    return clean, actions

# Metrics most useful to surface a recent value for, in context.
_RECENT = ["sleep_score", "hrv", "resting_hr", "vo2max", "body_fat_pct"]


def _fmt_rank(r) -> str:
    return f"{r['tier']} {r['sub']} (top {r['top_pct']:.0f}%)" if r else "unranked"


def build_context(samples, habits=None, profile=None) -> str:
    """A compact, PII-free USER DATA block from canonical samples + app-supplied
    habits/profile. `habits` items: {title, category?, done_today?, streak?}."""
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


def compose_system(samples, habits=None, profile=None) -> str:
    return f"{SYSTEM_PROMPT}\n\n=== USER DATA ===\n{build_context(samples, habits, profile)}"


def context_sections(samples, habits=None, profile=None) -> dict:
    """The exact context the coach holds, as labelled sections — powers the
    transparency view so the user sees precisely what is (and isn't) shared."""
    habits = habits or []
    out = {
        "profile": None, "overall": None, "categories": {},
        "weakest": None, "strongest": None, "recent": {}, "habits": [],
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
