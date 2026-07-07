"""The backend must import the canonical engine and cover every ranked metric
the client registry expects — guards the Python↔Dart drift that this slice fixed.
"""
import pytest

from app import engine as E
from app.registry import RANKED_CATEGORY


def test_engine_loaded():
    assert len(E.STANDARDS) >= 22
    assert "sleep_score" in E.STANDARDS  # the standardised one


def test_every_registry_metric_has_a_standard():
    missing = [m for m in RANKED_CATEGORY if m not in E.STANDARDS]
    assert not missing, f"engine missing standards for: {missing}"


def test_strength_requires_bodyweight():
    with pytest.raises(ValueError):
        E.tier_of("bench", 100)  # no bodyweight-at-time


def test_direction_lower_is_better():
    assert E.percentile("resting_hr", 50) > E.percentile("resting_hr", 80)
    assert E.percentile("body_fat_pct", 10) > E.percentile("body_fat_pct", 30)


# ── Rank sanity pass (owner ask: "Immersion ranks sanity check") ────────────
# Property-checks EVERY standard so a mis-anchored distribution can't ship:
# the tier ladder must be ordered, percentiles monotone + bounded, and a few
# human-plausible anchor values must land in plausible tiers.

def test_rank_sanity_every_metric_ladder_ordered_and_bounded():
    bw = 80.0
    for mid, std in E.STANDARDS.items():
        rungs = [E.threshold(mid, t, bw) for t in E.TIERS[1:]]  # entry values above Wood
        pairs = list(zip(rungs, rungs[1:]))
        if std.ideal is not None or std.direction == -1:
            assert all(b <= a + 1e-9 for a, b in pairs), f"{mid}: ladder not descending"
        else:
            assert all(b >= a - 1e-9 for a, b in pairs), f"{mid}: ladder not ascending"
        ps = [E.percentile(mid, v, bw) for v in rungs]
        assert all(0.0 <= p <= 1.0 for p in ps), f"{mid}: percentile out of bounds"
        assert all(b >= a - 1e-9 for a, b in zip(ps, ps[1:])), f"{mid}: percentile not monotone"
        rvs = [E.tier_of(mid, v, bw)["rank_value"] for v in rungs]
        assert all(0.0 <= rv <= 9.0 for rv in rvs), f"{mid}: rank_value out of bounds"
        assert all(b >= a - 1e-9 for a, b in zip(rvs, rvs[1:])), f"{mid}: rank_value not monotone"


def test_rank_sanity_plausible_values_land_in_plausible_tiers():
    # Anchors so a broken standard can't hide behind self-consistent monotonicity.
    assert 2.5 < E.tier_of("bench", 60, 80)["rank_value"] < 5.0    # 0.75x BW: middling
    assert E.tier_of("bench", 130, 80)["rank_value"] > 5.5         # 1.6x BW: advanced
    assert E.tier_of("vo2max", 35)["rank_value"] < 2.0             # sedentary
    assert E.tier_of("vo2max", 65)["rank_value"] > 5.5             # near-elite aerobic
    assert E.tier_of("resting_hr", 45)["rank_value"] > 6.5         # athlete RHR
    assert E.tier_of("resting_hr", 75)["rank_value"] < 3.0
    assert E.tier_of("plank", 240)["rank_value"] > E.tier_of("plank", 60)["rank_value"] + 3


def test_rank_sanity_ideal_targets_plateau_not_reward_extremes():
    # Health targets (body fat / BP): AT the ideal = capped just inside Glory;
    # leaner-than-ideal is NOT ranked higher (no reward for underweight), and
    # well above the ideal falls off honestly.
    for mid in ("body_fat_pct", "blood_pressure"):
        ideal = E.STANDARDS[mid].ideal
        at = E.tier_of(mid, ideal)["rank_value"]
        below = E.tier_of(mid, ideal * 0.7)["rank_value"]
        assert at < 9.0 and abs(below - at) < 1e-9, mid
        assert E.tier_of(mid, ideal * 2.0)["rank_value"] < at - 2, mid
