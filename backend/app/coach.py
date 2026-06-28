"""AI coach (PDF Part 5) — context assembly, system prompt, and agentic-action
parsing. Pure helpers (unit-tested); the Gemini network call lives in the router.

The APP is authoritative: it holds the full local data and the canonical rank engine,
so it sends computed ranks, trends, day-aligned correlations, workout sets, and rich
habits (targets + measured-vs-target). The backend formats that into a disciplined,
PII-free analyst brief. Falls back to its own sample-derived ranks when the app omits
them. Identifiers are never sent."""
import json
import re

from .ranking import compute_ranks

SYSTEM_PROMPT = (
    "You are Physical's AI coach — a rigorous, disciplined strength-and-conditioning and "
    "health scientist. Serious and precise, but encouraging and never preachy. Physical "
    "ranks every trainable metric in PERCENTILE space against the general young-male "
    "population, in tiers Wood→Bronze→Silver→Gold→Platinum→Diamond→Champion→Titan→Glory "
    "(each split I/II/III, I lowest). The overall rank is the weighted average of four "
    "category ranks (Performance, Strength, Recovery, Aesthetics).\n\n"
    "METHOD — follow this on every substantive answer:\n"
    "1. OBSERVE: cite the exact numbers from USER DATA (rank, value, r, trend). Never "
    "invent a number; if something needed is missing, say so and tell them precisely what "
    "to log or sync.\n"
    "2. EXPLAIN: give the mechanism — WHY it matters physiologically — in plain, correct "
    "terms. Full explanations, not one-liners.\n"
    "3. PRESCRIBE: one to three concrete, measurable, time-bound actions targeting the "
    "highest-leverage weakness first (lowest-ranked category/metric moves the overall "
    "most). State the expected effect and how you'll know it worked.\n"
    "4. ITERATE: compare against the provided TRENDS and habit adherence/streaks. Name "
    "the pattern (improving / plateauing / regressing), and adjust the plan accordingly — "
    "progress a stalled lift, deload a fatigued one, or retune a habit target that's too "
    "easy or too hard.\n\n"
    "CORRELATIONS — you are given REAL day-aligned Pearson correlations (r, with n = the "
    "number of overlapping days). When one is relevant: state its strength and direction, "
    "propose a plausible mechanism, and ALWAYS caveat that correlation is not causation and "
    "note the sample size (small n = tentative). Suggest a simple experiment to test it, and "
    "pin the important ones so they're tracked.\n"
    "WORKOUT SETS — you can read individual sets (weight×reps per exercise). Use them to "
    "judge per-muscle volume, intensity, balance, and week-to-week progression; flag "
    "imbalances, missing muscle groups, and junk volume.\n"
    "RECOVERY AUTO-REGULATION — if sleep score, HRV, resting HR or readiness are poor or "
    "trending down, proactively ease the plan: lighten/remove a heavy training habit and/or "
    "add a short mobility or recovery habit.\n"
    "AESTHETICS — habits can list the products used; reason about them specifically (active "
    "ingredients, routine gaps) when advising on skin/hair/oral.\n\n"
    "You are a coach, not a clinician: do not diagnose or give medical treatment advice; "
    "for anything medical, briefly say to consult a professional. Be thorough yet readable: "
    "use short bold headers or tight bullets; no filler.\n\n"
    "AGENTIC ACTIONS — when you recommend a concrete change to their habits or dashboard, "
    "append a fenced block so they can apply it in one tap (they always confirm). Use "
    "exactly one JSON object per block:\n"
    "```action\n"
    '{"type": "add_habit", "title": "Mobility flow", "category": "performance", '
    '"durationMins": 10, "time": "07:00"}\n'
    "```\n"
    "Other types:\n"
    '- {"type": "remove_habit", "title": "<existing habit title>"}\n'
    '- {"type": "adjust_habit_target", "title": "<existing habit title>", "target": 165, '
    '"compare": "gte"}  (retune a target that\'s too easy/hard)\n'
    '- {"type": "pin_correlation", "a": "<metric_id>", "b": "<metric_id>"}\n'
    "category is one of sleep|exercise|diet|aesthetics|recovery|misc. Metric ids look like "
    "sleep_score, hrv, resting_hr, vo2max, bench, squat, ohp, pullup, body_fat_pct. Include "
    "only fields you mean; propose at most two actions per reply, and only when clearly useful."
)

_ACTION_RE = re.compile(r"```action\s*(\{.*?\})\s*```", re.DOTALL)
_ACTION_TYPES = {"add_habit", "remove_habit", "adjust_habit_target", "pin_correlation"}
_CATEGORIES = {"sleep", "exercise", "diet", "aesthetics", "recovery", "misc"}
_TIME_RE = re.compile(r"^\d{1,2}:\d{2}$")


def parse_actions(text: str):
    """Extract validated agentic actions from ```action blocks, returning
    (clean_text_without_blocks, actions). Malformed blocks are ignored — never raises."""
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
        elif t == "adjust_habit_target":
            tgt = obj.get("target")
            if isinstance(tgt, (int, float)) and not isinstance(tgt, bool):
                act = {"type": t, "title": title, "target": float(tgt)}
                if obj.get("compare") in ("gte", "lte"):
                    act["compare"] = obj["compare"]
                actions.append(act)
        else:  # remove_habit
            actions.append({"type": t, "title": title})
    clean = _ACTION_RE.sub("", text).strip()
    return clean, actions


# Metrics most useful to surface a recent value for, in context.
_RECENT = ["sleep_score", "hrv", "resting_hr", "vo2max", "body_fat_pct"]
_TREND_ARROW = {"up": "↑", "down": "↓", "flat": "→"}


def _fmt_rank(r) -> str:
    if not r:
        return "unranked"
    sub = f" {r['sub']}" if r.get("sub") else ""
    return f"{r['tier']}{sub} (top {r['top_pct']:.0f}%)"


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
    if diet.get("health"):
        extra += f", diet-health {int(diet['health'])}/100"
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


def _rank_lines(ranks: dict | None, samples) -> list[str]:
    """Prefer the app's complete computed ranks; fall back to sample-derived ranks."""
    lines: list[str] = []
    if ranks and ranks.get("overall"):
        lines.append(f"Overall rank: {_fmt_rank(ranks['overall'])}")
        cats = ranks.get("categories") or {}
        if cats:
            lines.append("Categories: " + ", ".join(f"{c} {_fmt_rank(r)}" for c, r in cats.items()))
        mets = ranks.get("metrics") or []
        if mets:
            srt = sorted(mets, key=lambda m: m.get("rank_value", m.get("top_pct", 100)))
            def one(m):
                arrow = _TREND_ARROW.get(m.get("trend", ""), "")
                val = f"={m['value']:g}" if m.get("value") is not None else ""
                return f"{m.get('label', m.get('id'))} {_fmt_rank(m)}{val}{arrow}"
            lines.append("Weakest → strongest: " + "; ".join(one(m) for m in srt))
        return lines
    if samples:
        overall, categories, metrics = compute_ranks(samples)
        lines.append(f"Overall rank: {_fmt_rank(overall)}")
        if categories:
            lines.append("Categories: " + ", ".join(f"{c} {_fmt_rank(r)}" for c, r in categories.items()))
        ranked = sorted(metrics.items(), key=lambda kv: kv[1]["rank_value"])
        if ranked:
            w, s = ranked[0], ranked[-1]
            lines.append(f"Weakest: {w[0]} {_fmt_rank(w[1])}. Strongest: {s[0]} {_fmt_rank(s[1])}.")
        recent = [f"{m} {metrics[m]['value']:g}" for m in _RECENT if m in metrics]
        if recent:
            lines.append("Recent readings: " + ", ".join(recent))
    else:
        lines.append("No logged or synced data yet.")
    return lines


def _trend_lines(trends: dict | None) -> str | None:
    if not trends:
        return None
    parts = []
    for mid, t in list(trends.items())[:12]:
        arrow = _TREND_ARROW.get(t.get("direction", "flat"), "→")
        chg = t.get("change")
        chg_s = f" {chg:+g}" if isinstance(chg, (int, float)) else ""
        recent = t.get("recent") or []
        tail = f" [{', '.join(f'{v:g}' for v in recent[-6:])}]" if recent else ""
        parts.append(f"{mid} {arrow}{chg_s}{tail}")
    return "Trends (recent): " + " | ".join(parts) if parts else None


def _correlation_lines(correlations) -> str | None:
    if not correlations:
        return None
    rows = []
    for c in correlations[:14]:
        a, b, r, n = c.get("a"), c.get("b"), c.get("r"), c.get("n")
        if a is None or b is None or r is None:
            continue
        rows.append(f"{a} ↔ {b}: r={r:+.2f} (n={int(n or 0)})")
    return "Day-aligned correlations: " + "; ".join(rows) if rows else None


def _sets_lines(workout_sets) -> str | None:
    if not workout_sets:
        return None
    out = []
    for s in workout_sets[:6]:
        exs = []
        for e in (s.get("exercises") or [])[:8]:
            sets = e.get("sets") or []
            shown = ", ".join(
                (f"{st.get('w')}×{st.get('r')}" if st.get("w") is not None and st.get("r") is not None
                 else (f"{st.get('r')} reps" if st.get("r") is not None else "·"))
                for st in sets[:8])
            exs.append(f"{e.get('name', '?')} ({shown})" if shown else e.get("name", "?"))
        if exs:
            out.append(f"{s.get('date', '?')} {s.get('type', '')}: " + "; ".join(exs))
    return "Recent sets:\n  " + "\n  ".join(out) if out else None


def _habit_lines(habits) -> str | None:
    if not habits:
        return None
    done = sum(1 for h in habits if h.get("done_today") or h.get("met"))
    items = []
    for h in habits[:16]:
        bits = [h.get("title", "?")]
        if h.get("section") or h.get("category"):
            bits.append(f"[{h.get('section') or h.get('category')}]")
        if h.get("target") is not None:
            cmp = "≤" if h.get("compare") == "lte" else "≥"
            meas = h.get("measured")
            meas_s = f"{meas:g}" if isinstance(meas, (int, float)) else "–"
            bits.append(f"{meas_s}{cmp}{h['target']:g}{h.get('unit', '')}")
        if h.get("met") or h.get("done_today"):
            bits.append("✓done")
        if h.get("streak"):
            bits.append(f"streak {int(h['streak'])}")
        if h.get("adherence") is not None:
            bits.append(f"{int(h['adherence'])}% adherence")
        if h.get("products"):
            bits.append("uses " + ", ".join(h["products"][:6]))
        items.append(" ".join(bits))
    return f"Habits ({done}/{len(habits)} done today):\n  " + "\n  ".join(items)


def build_context(samples, habits=None, profile=None, diet=None, training=None,
                  aesthetics=None, ranks=None, trends=None, correlations=None,
                  workout_sets=None) -> str:
    """A compact, PII-free analyst brief from app-computed context (+ sample fallback)."""
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

    lines += _rank_lines(ranks, samples)

    for line in (_trend_lines(trends), _correlation_lines(correlations),
                 _diet_line(diet), _training_line(training), _sets_lines(workout_sets),
                 _aesthetics_line(aesthetics), _habit_lines(habits)):
        if line:
            lines.append(line)
    if not habits:
        lines.append("No habits set yet.")
    return "\n".join(lines)


def compose_system(samples, habits=None, profile=None, diet=None, training=None,
                   aesthetics=None, ranks=None, trends=None, correlations=None,
                   workout_sets=None) -> str:
    ctx = build_context(samples, habits, profile, diet, training, aesthetics,
                        ranks, trends, correlations, workout_sets)
    return f"{SYSTEM_PROMPT}\n\n=== USER DATA ===\n{ctx}"


def context_sections(samples, habits=None, profile=None, diet=None, training=None,
                     aesthetics=None, ranks=None, trends=None, correlations=None,
                     workout_sets=None) -> dict:
    """The exact context the coach holds, as labelled sections — powers the
    transparency view so the user sees precisely what is (and isn't) shared."""
    habits = habits or []
    out = {
        "profile": None, "overall": None, "categories": {},
        "weakest": None, "strongest": None, "recent": {},
        "trends": _trend_lines(trends), "correlations": _correlation_lines(correlations),
        "diet": _diet_line(diet), "training": _training_line(training),
        "sets": _sets_lines(workout_sets), "aesthetics": _aesthetics_line(aesthetics),
        "habits": [],
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
    if ranks and ranks.get("overall"):
        out["overall"] = _fmt_rank(ranks["overall"])
        out["categories"] = {c: _fmt_rank(r) for c, r in (ranks.get("categories") or {}).items()}
        mets = sorted(ranks.get("metrics") or [],
                      key=lambda m: m.get("rank_value", m.get("top_pct", 100)))
        if mets:
            out["weakest"] = f"{mets[0].get('label', mets[0].get('id'))} — {_fmt_rank(mets[0])}"
            out["strongest"] = f"{mets[-1].get('label', mets[-1].get('id'))} — {_fmt_rank(mets[-1])}"
        out["recent"] = {m["id"]: m["value"] for m in (ranks.get("metrics") or [])
                         if m.get("id") in _RECENT and m.get("value") is not None}
    elif samples:
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
        + (f" [{h.get('section') or h.get('category')}]" if (h.get('section') or h.get("category")) else "")
        + (f" · streak {int(h['streak'])}" if h.get("streak") else "")
        + (" · done today" if (h.get("met") or h.get("done_today")) else "")
        for h in habits
    ]
    return out
