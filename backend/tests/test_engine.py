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
    # Sit-and-reach is CM PAST THE TOES: touching them is ~median young man
    # (Silver-ish), not bottom 0.1% — the pre-audit N(15,5) failure mode.
    assert 1.5 < E.tier_of("hamstring_mobility", 0)["rank_value"] < 3.5
    assert E.tier_of("hamstring_mobility", -10)["rank_value"] < 1.0   # 10cm short: stiff
    assert E.tier_of("hamstring_mobility", 15)["rank_value"] > 4.5    # +15cm: genuinely flexible
    # ~25 push-ups/min is a median young man, ~40 is strong, not mid-table.
    assert 2.0 < E.tier_of("pushups", 25)["rank_value"] < 3.5
    assert E.tier_of("pushups", 40)["rank_value"] > 4.0
    # Pullup standard reads TOTAL system weight: one strict bodyweight pullup
    # already beats the median (many young men can't do one).
    assert E.tier_of("pullup", E.strength_value("pullup", 75, 1), 75)["rank_value"] > 2.5


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


# ── Accessory-lift immersion (est-1RM change) — lock in the calibration ──────
# Accessories now rank on capped est-1RM like the compounds. These pin the
# verified behaviour so the anchors/formula can't silently drift.

_ISO = ["curl", "lateral_raise", "skull_crusher", "forearm_curl"]


def test_accessory_est1rm_rewards_strength_over_grinding():
    for mid in _ISO:
        assert E.strength_value(mid, 12.5, 8) > E.strength_value(mid, 10, 12), mid
    # Reps beyond 12 are capped — no runaway inflation from high-rep grinding.
    assert E.strength_value("curl", 20, 12) == E.strength_value("curl", 20, 30)


def test_accessory_realistic_sets_land_in_sane_tiers():
    bw = 80
    def rv(mid, w, r):
        return E.tier_of(mid, E.strength_value(mid, w, r), bw)["rank_value"]
    # A weak beginner set is low; a solid intermediate set is mid; a strong set is high.
    assert rv("curl", 8, 12) < 1.5                    # ~11kg 1RM — novice
    assert 3.0 < rv("curl", 20, 8) < 5.0              # ~25kg 1RM — intermediate Gold/Plat
    assert rv("curl", 40, 4) > 5.0                    # ~44kg 1RM — advanced Diamond+
    assert 3.0 < rv("lateral_raise", 10, 12) < 5.0    # a real 10kg lateral raise → Gold/Plat
    assert rv("skull_crusher", 20, 10) > 3.0


def test_accessory_glory_requires_an_elite_load_not_rep_grinding():
    bw = 80
    def rv(mid, w, r):
        return E.tier_of(mid, E.strength_value(mid, w, r), bw)["rank_value"]
    # Grinding light weight for many reps never approaches Glory (the old bug).
    assert rv("curl", 12, 12) < 6.0
    assert rv("lateral_raise", 8, 15) < 6.0
    # Glory (rv ≥ 8) needs a genuinely elite load — for a curl that's ~1x+ bodyweight.
    assert rv("curl", 80, 5) >= 8.0


def test_accessories_do_not_wildly_distort_the_strength_category():
    L = lambda mid, w, r: E.Log(mid, E.strength_value(mid, w, r), 80)
    compounds = [L("bench", 90, 5), L("squat", 125, 5), L("deadlift", 160, 5), L("ohp", 55, 5)]
    accessories = [L("curl", 20, 10), L("lateral_raise", 10, 12),
                   L("skull_crusher", 25, 10), L("forearm_curl", 20, 12)]
    comp = E.overall(compounds)["rank_value"]
    both = E.overall(compounds + accessories)["rank_value"]
    # Adding accessories shifts the category by less than a full tier — no distortion.
    assert abs(both - comp) < 1.0
