"""AI coach (PDF Part 5) — context assembly + system prompt. Pure helpers so the
prompt is unit-tested; the Gemini network call lives in the router. Only metrics,
ranks, and habits go to the model — never identifiers (PII-scrubbed).
"""
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
    "missing, say so and suggest logging or syncing it rather than guessing."
)

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
