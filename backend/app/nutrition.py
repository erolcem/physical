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

# Diet-health radar axes. The model rates each food's QUALITY DENSITY per axis
# (0–100, portion-independent — how strongly 100 kcal of this food exhibits the
# quality); the PORTION math is done here deterministically:
#     points = density × (portion kcal / 2000 kcal reference day)
# so a 2000-kcal day of density-80 food lands the axis at 80, junk calories
# contribute ~0 (they no longer "count for free"), and under-eating scales down
# honestly. Points accumulate across the day capped at 100 per axis. The fibre and
# micronutrient axes are recomputed EXACTLY in the app from grams vs targets — the
# AI densities are the fallback. Keep keys in sync with diet.dart `healthAxisLabels`.
HEALTH_AXES = ("micronutrients", "fibre", "gut_health", "antioxidants",
               "healthy_fats", "whole_food")
_REFERENCE_DAY_KCAL = 2000.0

NUTRITION_PROMPT = (
    "You are a precise nutrition estimator. Given a food or meal description, "
    "estimate its nutrition for the portion described (assume one typical serving "
    "if no quantity is given). Respond with ONLY a JSON object — no prose, no "
    "markdown fences. Keys: calories (kcal), protein, carbs, fat, fibre (all in "
    "grams), and these micronutrients in the stated units: "
    + ", ".join(f"{k} ({u})" for k, u in MICRO_UNITS.items())
    + ". Also include a \"health\" object rating this FOOD's quality density 0-100 "
    "per diet-health axis, INDEPENDENT of portion size (how strongly a typical "
    "calorie of this food exhibits the quality; e.g. spinach antioxidants ~90, "
    "soda ~0): " + ", ".join(HEALTH_AXES)
    + " (whole_food = minimally-processed/whole vs ultra-processed). "
    "All values plain numbers; use 0 for negligible amounts. Approximate honestly."
)

# Appended when the request carries a meal photo. The photo is a SUPPLEMENT: the
# typed description stays the source of truth for WHAT was eaten (never
# photo-alone — visual food ID is too error-prone), while the image sharpens the
# parts a description underdetermines (portion size, preparation, sides).
PHOTO_HINT = (
    " A photo of the meal is attached. The text description is authoritative for "
    "WHAT the food is; use the photo to refine PORTION SIZE, preparation and "
    "composition (e.g. how much rice is actually on the plate, fried vs grilled, "
    "sauces or sides the text omitted). If the photo contradicts the text about "
    "what the food is, trust the text."
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
    # Density (0–100, portion-independent) → points for THIS portion: density
    # weighted by its share of a 2000-kcal reference day. Junk calories therefore
    # dilute the day instead of adding "free" health points.
    kcal_frac = min(1.0, (out["calories"] or 0.0) / _REFERENCE_DAY_KCAL)
    health = {}
    for k in HEALTH_AXES:
        v = _num(hsrc.get(k))
        if v is not None:
            health[k] = round(min(100.0, v) * kcal_frac, 2)
    out["health"] = health

    # Reject all-zero results (junk input) so the app never shows a fake "0 kcal".
    if out["calories"] == 0 and not any(out[k] for k in ("protein", "carbs", "fat")):
        return None
    return out
