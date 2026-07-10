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
    "to log or sync. Ranks score the FULL roster: unlogged metrics count as worst-case, so "
    "use COVERAGE to tell 'untested' apart from genuinely weak — if coverage is low, the "
    "highest-leverage move is often simply logging/measuring the gaps.\n"
    "2. EXPLAIN: give the mechanism — WHY it matters physiologically — in plain, correct "
    "terms. Full explanations, not one-liners.\n"
    "3. PRESCRIBE: one to three concrete, measurable, time-bound actions targeting the "
    "highest-leverage weakness first (lowest-ranked category/metric moves the overall "
    "most). State the expected effect and how you'll know it worked.\n"
    "4. ITERATE: compare against the provided TRENDS and habit adherence/streaks. Name "
    "the pattern (improving / plateauing / regressing), and adjust the plan accordingly — "
    "progress a stalled lift, deload a fatigued one, or retune a habit target that's too "
    "easy or too hard.\n\n"
    "RAW HISTORY — you are given the downsampled daily history of EVERY metric (ranked AND "
    "background, e.g. steps, resting HR, deep sleep). Read it directly and make your OWN "
    "connections — lags, weekday effects, what moved before a rank changed — not only the "
    "pre-computed correlations.\n"
    "ENERGY & WEIGHT — relate daily calories IN (food) to estimated calories OUT "
    "(BMR × 1.2 everyday activity + tracked workout kcal; an ESTIMATE) and the bodyweight "
    "trend in the history. If intake/expenditure and actual weight change disagree, say so "
    "and adjust the calorie target or note the estimate is off (e.g. recommend changing "
    "the calorie-out assumption or intake). MEALS carry an eaten-at time — use meal TIMING "
    "(late-night eating, skipped breakfasts, pre/post-workout fueling) as real signal.\n"
    "CROSS-REFERENCE HABITS — when discussing a rank/metric's performance, look at the "
    "relevant section's HABITS and their adherence (e.g. a lagging bench → chest/strength "
    "habits; poor recovery → sleep/recovery habits) and say which habit to add/change.\n"
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
    "AGENTIC ACTIONS — when you recommend a concrete change, propose it by CALLING the "
    "provided function so the user can apply it in one tap (they always confirm): "
    "add_habit, remove_habit, adjust_habit_target (retune a target that's too easy/hard), "
    "pin_correlation (watch a metric pair), or pin_note (save a short standing goal/context "
    "note — e.g. a target weight + date, an injury constraint — that you'll then see in every "
    "future chat under 'Pinned by user'). ALWAYS also explain it in your text reply — "
    "never reply with only a function call. category is one of "
    "sleep|exercise|diet|aesthetics|recovery|misc; metric ids look like sleep_score, hrv, "
    "resting_hr, vo2max, bench, squat, ohp, pullup, body_fat_pct. Propose at most two "
    "actions per reply, and only when clearly useful."
)

# Tool declarations for Gemini function-calling — the model proposes these; the app
# applies each behind a one-tap confirmation.
ACTION_TOOLS = [
    {
        "name": "add_habit",
        "description": "Add a new habit to the user's checklist (user confirms).",
        "parameters": {"type": "object", "properties": {
            "title": {"type": "string", "description": "Short habit name"},
            "category": {"type": "string",
                         "enum": ["sleep", "exercise", "diet", "aesthetics", "recovery", "misc"]},
            "durationMins": {"type": "integer"},
            "time": {"type": "string", "description": "Ideal time HH:MM"},
        }, "required": ["title"]},
    },
    {
        "name": "remove_habit",
        "description": "Remove an existing habit by its exact title.",
        "parameters": {"type": "object", "properties": {
            "title": {"type": "string"}}, "required": ["title"]},
    },
    {
        "name": "adjust_habit_target",
        "description": "Retune an existing habit's numeric target.",
        "parameters": {"type": "object", "properties": {
            "title": {"type": "string"},
            "target": {"type": "number"},
            "compare": {"type": "string", "enum": ["gte", "lte"]},
        }, "required": ["title", "target"]},
    },
    {
        "name": "pin_correlation",
        "description": "Pin a metric pair to the dashboard to track over time.",
        "parameters": {"type": "object", "properties": {
            "a": {"type": "string"}, "b": {"type": "string"}}, "required": ["a", "b"]},
    },
    {
        "name": "pin_note",
        "description": ("Pin a short standing goal/context note the coach should always "
                        "remember (lives in the user's pin section; user confirms)."),
        "parameters": {"type": "object", "properties": {
            "text": {"type": "string",
                     "description": "≤120 chars, e.g. 'Cutting to 78 kg by September'"}},
            "required": ["text"]},
    },
]

_ACTION_RE = re.compile(r"```action\s*(\{.*?\})\s*```", re.DOTALL)
_ACTION_TYPES = {"add_habit", "remove_habit", "adjust_habit_target", "pin_correlation",
                 "pin_note"}
_CATEGORIES = {"sleep", "exercise", "diet", "aesthetics", "recovery", "misc"}
_TIME_RE = re.compile(r"^\d{1,2}:\d{2}$")


def _validate_action(obj: dict) -> dict | None:
    """Validate one action dict ({"type": ..., ...}) → a clean action or None."""
    t = obj.get("type")
    if t not in _ACTION_TYPES:
        return None
    if t == "pin_correlation":
        a, b = str(obj.get("a", "")).strip(), str(obj.get("b", "")).strip()
        return {"type": t, "a": a, "b": b} if (a and b and a != b) else None
    if t == "pin_note":
        text = str(obj.get("text", "")).strip()[:120]
        return {"type": t, "text": text} if text else None
    title = str(obj.get("title", "")).strip()[:60]
    if not title:
        return None
    if t == "add_habit":
        act = {"type": t, "title": title,
               "category": obj.get("category") if obj.get("category") in _CATEGORIES else "misc"}
        dur = obj.get("durationMins")
        if isinstance(dur, (int, float)) and not isinstance(dur, bool):
            act["durationMins"] = int(dur)
        tm = obj.get("time")
        if isinstance(tm, str) and _TIME_RE.match(tm):
            act["time"] = tm
        return act
    if t == "adjust_habit_target":
        tgt = obj.get("target")
        if isinstance(tgt, (int, float)) and not isinstance(tgt, bool):
            act = {"type": t, "title": title, "target": float(tgt)}
            if obj.get("compare") in ("gte", "lte"):
                act["compare"] = obj["compare"]
            return act
        return None
    return {"type": t, "title": title}  # remove_habit


def parse_actions(text: str):
    """Extract validated actions from ```action blocks (a text fallback for models that
    don't use tool-calling). Returns (clean_text_without_blocks, actions)."""
    actions = []
    for m in _ACTION_RE.finditer(text):
        try:
            obj = json.loads(m.group(1))
        except Exception:
            continue
        a = _validate_action(obj)
        if a:
            actions.append(a)
    return _ACTION_RE.sub("", text).strip(), actions


def actions_from_calls(calls) -> list[dict]:
    """Validated actions from Gemini function calls ([{"name", "args"}, ...])."""
    out = []
    for c in (calls or []):
        name = c.get("name")
        if not name:
            continue
        args = c.get("args") if isinstance(c.get("args"), dict) else {}
        a = _validate_action({"type": name, **args})
        if a:
            out.append(a)
    return out


def dedupe_actions(actions: list[dict]) -> list[dict]:
    seen, out = set(), []
    for a in actions:
        key = (a.get("type"), a.get("title", ""), a.get("a", ""), a.get("b", ""),
               a.get("text", ""))
        if key in seen:
            continue
        seen.add(key)
        out.append(a)
    return out


_EMAIL_RE = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")
_LONGNUM_RE = re.compile(r"\b\d{10,}\b")


def scrub_pii(s: str) -> str:
    """Defence-in-depth: strip emails and long digit runs (phone/account ids) before any
    cloud call. The app already sends only metrics/ranks/habits — this is a safety net."""
    return _LONGNUM_RE.sub("[redacted]", _EMAIL_RE.sub("[redacted]", s))


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
            def _rv(m):
                v = m.get("rank_value", m.get("top_pct", 100))
                return v if isinstance(v, (int, float)) else 100.0  # None-safe sort key
            srt = sorted(mets, key=_rv)
            def one(m):
                arrow = _TREND_ARROW.get(m.get("trend", ""), "")
                val = f"={m['value']:g}" if m.get("value") is not None else ""
                return f"{m.get('label', m.get('id'))} {_fmt_rank(m)}{val}{arrow}"
            lines.append("Weakest → strongest: " + "; ".join(one(m) for m in srt))
        cov = ranks.get("coverage") or {}
        if cov:
            ov = cov.get("overall") or {}
            parts = [f"{k} {v['logged']}/{v['total']}" for k, v in cov.items() if k != "overall"]
            head = f"{ov.get('logged', 0)}/{ov.get('total', 0)} metrics logged" if ov else ""
            lines.append(f"Coverage ({head}): " + ", ".join(parts)
                         + ". Unlogged metrics count as WORST — a low rank here may be UNTESTED,"
                         " not weak; prioritise logging/measuring the gaps to raise it.")
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
    for c in correlations[:20]:
        a, b, r, n = c.get("a"), c.get("b"), c.get("r"), c.get("n")
        if a is None or b is None or r is None:
            continue
        rows.append(f"{a} ↔ {b}: r={r:+.2f} (n={int(n or 0)})")
    return "Day-aligned correlations: " + "; ".join(rows) if rows else None


def _history_lines(hist) -> str | None:
    if not hist:
        return None
    # Deliberately HUGE: Pro-class context windows take this easily, and the coach
    # is explicitly instructed to read the raw series and draw its own connections
    # (not just the pre-computed correlations). Up to 100 metrics × 180 points ≈
    # two downsampled years of everything.
    rows = []
    for mid, vals in list(hist.items())[:100]:
        if not vals:
            continue
        rows.append(f"{mid}: " + ", ".join(f"{v:g}" for v in vals[-180:]))
    return ("Full metric history (downsampled daily, oldest→newest):\n  " + "\n  ".join(rows)) if rows else None


def _pins_lines(pins) -> str | None:
    """The user's standing pins — goals/context the coach must always honour."""
    items = [str(p).strip()[:160] for p in (pins or []) if str(p).strip()]
    if not items:
        return None
    return "Pinned by user (standing goals/context — always factor these in):\n  " + \
        "\n  ".join(f"📌 {p}" for p in items[:20])


def _history_summary(hist) -> str | None:
    """Transparency-sheet form of the raw history: what's shared, not the values
    themselves (100 metrics × 180 points would drown the sheet)."""
    if not hist:
        return None
    series = [(mid, len(vals)) for mid, vals in list(hist.items())[:100] if vals]
    if not series:
        return None
    pts = max(n for _, n in series)
    return (f"Raw daily history for {len(series)} metric"
            f"{'s' if len(series) != 1 else ''} × up to {min(pts, 180)} points each "
            "(downsampled, up to 2 years)")


def _energy_lines(energy) -> str | None:
    if not energy:
        return None
    parts = []
    if energy.get("in"):
        parts.append("kcal in: " + ", ".join(str(int(x)) for x in (energy["in"] or [])[-30:]))
    if energy.get("out"):
        parts.append("est kcal out: " + ", ".join(str(int(x)) for x in (energy["out"] or [])[-30:]))
    if energy.get("bmr"):
        parts.append(f"BMR ~{int(energy['bmr'])}")
    return ("Energy balance (daily, oldest→newest): " + "; ".join(parts)) if parts else None


def _meals_lines(meals) -> str | None:
    """The actual meals of the last days — food quality/timing/repetition, not
    just totals."""
    if not meals:
        return None
    by_day: dict[str, list[str]] = {}
    for m in meals[:120]:
        d = str(m.get("d", "?"))
        bits = f"{m.get('n', '?')} ({int(m.get('kcal') or 0)}kcal, {int(m.get('p') or 0)}g P"
        if m.get("fib"):
            bits += f", {int(m['fib'])}g fib"
        bits += ")"
        by_day.setdefault(d, []).append(bits)
    rows = [f"{d}: " + "; ".join(items) for d, items in list(by_day.items())[:14]]
    return "Meals (last days, newest first):\n  " + "\n  ".join(rows)


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
    for h in habits[:40]:
        bits = [h.get("title", "?")]
        if h.get("section") or h.get("category"):
            bits.append(f"[{h.get('section') or h.get('category')}]")
        if h.get("description"):
            bits.append(f"— {str(h['description'])[:160]}")
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
                  workout_sets=None, metric_history=None, energy=None,
                  meals=None, pins=None) -> str:
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

    for line in (_pins_lines(pins), _trend_lines(trends), _correlation_lines(correlations),
                 _energy_lines(energy), _diet_line(diet), _meals_lines(meals),
                 _training_line(training),
                 _sets_lines(workout_sets), _aesthetics_line(aesthetics),
                 _habit_lines(habits), _history_lines(metric_history)):
        if line:
            lines.append(line)
    if not habits:
        lines.append("No habits set yet.")
    return "\n".join(lines)


def compose_system(samples, habits=None, profile=None, diet=None, training=None,
                   aesthetics=None, ranks=None, trends=None, correlations=None,
                   workout_sets=None, metric_history=None, energy=None,
                   meals=None, pins=None) -> str:
    # Bulletproof: a malformed value on one device must never crash the coach for it.
    try:
        ctx = build_context(samples, habits, profile, diet, training, aesthetics,
                            ranks, trends, correlations, workout_sets, metric_history,
                            energy, meals, pins)
    except Exception:
        try:
            ctx = "\n".join(_rank_lines(ranks, samples))  # minimal safe fallback
        except Exception:
            ctx = "Data available but could not be summarised; ask the user what to focus on."
    return scrub_pii(f"{SYSTEM_PROMPT}\n\n=== USER DATA ===\n{ctx}")


def context_sections(samples, habits=None, profile=None, diet=None, training=None,
                     aesthetics=None, ranks=None, trends=None, correlations=None,
                     workout_sets=None, metric_history=None, energy=None,
                     meals=None, pins=None) -> dict:
    """The exact context the coach holds, as labelled sections — powers the
    transparency view so the user sees precisely what is (and isn't) shared."""
    habits = habits or []
    out = {
        "profile": None, "overall": None, "categories": {},
        "weakest": None, "strongest": None, "recent": {},
        "trends": _trend_lines(trends), "correlations": _correlation_lines(correlations),
        "diet": _diet_line(diet), "training": _training_line(training),
        "sets": _sets_lines(workout_sets), "aesthetics": _aesthetics_line(aesthetics),
        "meals": _meals_lines(meals), "energy": _energy_lines(energy),
        "history": _history_summary(metric_history),
        "pins": _pins_lines(pins),
        "coverage": None, "habits": [],
        "note": ("Only this data is sent to your AI coach. Your email, name, and "
                 "account id are never shared."),
    }
    if ranks and (ranks.get("coverage") or {}).get("overall"):
        ov = ranks["coverage"]["overall"]
        out["coverage"] = f"{ov.get('logged', 0)}/{ov.get('total', 0)} ranked metrics logged"
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
