"""Gemini-inferred nutrition (PDF Part 1 diet — macros + micronutrients).

A robust food database is hard to keep accurate, so we ask Gemini to estimate a
food's nutrition from its description. The model prompt + the defensive parser live
here (pure, unit-tested); the network call lives in the router. We request a FIXED
set of macros + micros in FIXED units (encoded in the key) so values sum cleanly
across foods, then coerce/clamp everything — the model may return prose, fences, or
junk, and this must never raise.
"""
import json
import re

# Canonical micronutrients we track, each in a fixed unit baked into the key name.
MICRO_UNITS = {
    "sodium_mg": "mg",
    "potassium_mg": "mg",
    "calcium_mg": "mg",
    "iron_mg": "mg",
    "magnesium_mg": "mg",
    "zinc_mg": "mg",
    "vitamin_c_mg": "mg",
    "vitamin_d_ug": "ug",
}
_MACROS = ("calories", "protein", "carbs", "fat", "fibre")

# Diet-health radar axes. Each food gets points 0–100 PER AXIS for the portion eaten,
# scaled so a full healthy day's foods sum to ~100 on each axis (i.e. one food is a
# fraction). They accumulate across the day → a radar + an averaged /100 diet-health
# score. Provisional (AI estimate). Keep keys in sync with diet.dart `healthAxisLabels`.
HEALTH_AXES = ("micronutrients", "fibre", "gut_health", "antioxidants",
               "healthy_fats", "whole_food")

NUTRITION_PROMPT = (
    "You are a precise nutrition estimator. Given a food or meal description, "
    "estimate its nutrition for the portion described (assume one typical serving "
    "if no quantity is given). Respond with ONLY a JSON object — no prose, no "
    "markdown fences. Keys: calories (kcal), protein, carbs, fat, fibre (all in "
    "grams), and these micronutrients in the stated units: "
    + ", ".join(f"{k} ({u})" for k, u in MICRO_UNITS.items())
    + ". Also include a \"health\" object scoring THIS food+portion's contribution "
    "to each diet-health axis as points 0-100, calibrated so a full day of healthy "
    "eating sums to about 100 per axis (so one item is a fraction): "
    + ", ".join(HEALTH_AXES)
    + " (whole_food = minimally-processed/whole vs ultra-processed). "
    "All values plain numbers; use 0 for negligible amounts. Approximate honestly."
)


def _num(v):
    """A finite, non-negative float, or None if [v] isn't a usable number."""
    if isinstance(v, bool) or not isinstance(v, (int, float, str)):
        return None
    try:
        f = float(v)
    except (TypeError, ValueError):
        return None
    if f != f or f in (float("inf"), float("-inf")):  # NaN / inf
        return None
    return max(0.0, round(f, 2))


def parse_nutrition(text: str):
    """Extract a nutrition dict {calories, protein, carbs, fat, fibre, micros{}}
    from a model reply, or None if unusable. Never raises."""
    if not text:
        return None
    m = re.search(r"\{.*\}", text, re.DOTALL)  # the JSON object even amid prose/fences
    if not m:
        return None
    try:
        obj = json.loads(m.group(0))
    except Exception:
        return None
    if not isinstance(obj, dict):
        return None

    out = {k: (_num(obj.get(k)) or 0.0) for k in _MACROS}
    src = obj.get("micros") if isinstance(obj.get("micros"), dict) else obj
    micros = {}
    for k in MICRO_UNITS:
        v = _num(src.get(k))
        if v is not None:
            micros[k] = v
    out["micros"] = micros

    hsrc = obj.get("health") if isinstance(obj.get("health"), dict) else obj
    health = {}
    for k in HEALTH_AXES:
        v = _num(hsrc.get(k))
        if v is not None:
            health[k] = min(100.0, v)  # cap one food's per-axis contribution
    out["health"] = health

    # Reject all-zero results (junk input) so the app never shows a fake "0 kcal".
    if out["calories"] == 0 and not any(out[k] for k in ("protein", "carbs", "fat")):
        return None
    return out
