"""Ranked-metric → category map for category scoring.

NOTE: this mirrors the ranked metrics in the Flutter registry
(`lib/data/metrics.dart`). It is the one piece intentionally duplicated for now;
keep it in sync with metrics.dart (a shared generated registry is a later step).
Only categories live here — direction / bodyweight-scaling come from the engine.
"""

RANKED_CATEGORY: dict[str, str] = {
    # strength
    "bench": "strength", "ohp": "strength", "lateral_raise": "strength",
    "curl": "strength", "skull_crusher": "strength", "forearm_curl": "strength",
    "pullup": "strength", "hip_thrust": "strength", "squat": "strength",
    "rdl": "strength", "calf_raise": "strength", "crunch": "strength",
    # performance
    "vo2max": "performance", "plank": "performance", "vert": "performance",
    "run5k_kmh": "performance", "deadhang": "performance",
    "hamstring_mobility": "performance", "pushups": "performance",
    "sprint_100m": "performance",
    # recovery (body_fat_pct lives here — it's a health metric)
    "resting_hr": "recovery", "hrv": "recovery", "sleep_score": "recovery",
    "body_fat_pct": "recovery", "blood_pressure": "recovery", "hrr": "recovery",
    # aesthetics (ranked, but EXCLUDED from the overall score — see ranking.py)
    "eye": "aesthetics", "voice": "aesthetics", "skin": "aesthetics",
    "oral": "aesthetics", "hair": "aesthetics", "grooming": "aesthetics",
}


def category_of(metric_id: str) -> str | None:
    return RANKED_CATEGORY.get(metric_id)
