"""
Physical — Rank Engine (reference implementation)  v0.3
=======================================================
Pure, deterministic reference. The Flutter app ports this to Dart; the FastAPI
backend imports it directly. Parity is enforced by golden_vectors.json.

CHANGES IN v0.3
  • Strength standards are now a TWO-COMPONENT MIXTURE per lift (untrained mass
    + trained tail) instead of a single guessed lognormal — see
    STANDARDS_METHODOLOGY.md §2. Grounded in: whole-population grip-strength
    norms (young men ~50 kg mean, normally distributed, CV ~0.18) for the
    untrained spread; CDC muscle-strengthening prevalence (~22% train seriously)
    for the mixture weight; trained standards for the tail. The mid/upper ranks
    are ~unchanged from v0.2 (bench bodyweight ≈ top 16%); the low end is now
    real rather than extrapolated.

CARRIED FROM v0.2
  • Bodyweight-at-time: strength scored against weight WHEN LIFTED (snapshot).
  • Allometric BW scaling (/BW^0.67); distribution-CDF percentiles; derived tier
    thresholds; explicit direction flag; z-space overall.

Strength MEDIANS are now data-grounded but the untrained component's centre is
still an estimate (untrained 1RMs are barely measured directly); flagged
provisional. Config-driven: tuning is a data edit, not a code change.
"""

from __future__ import annotations
from dataclasses import dataclass
from statistics import NormalDist
import math

# ─── Tiers ────────────────────────────────────────────────────────────────
TIERS = ["Wood", "Bronze", "Silver", "Gold", "Platinum",
         "Diamond", "Champion", "Titan", "Glory"]
TIER_TOP_PCT = {"Bronze": 80.0, "Silver": 60.0, "Gold": 40.0, "Platinum": 20.0,
                "Diamond": 10.0, "Champion": 3.0, "Titan": 1.0, "Glory": 0.1}
TIER_ENTRY_P = [0.0, 0.20, 0.40, 0.60, 0.80, 0.90, 0.97, 0.99, 0.999]
SUB = ["I", "II", "III"]
_Z = NormalDist()
_ALLO = 0.67


# ─── Distributions (Dist and MixtureDist share cdf/quantile) ───────────────
@dataclass(frozen=True)
class Dist:
    kind: str            # "normal" | "lognormal"
    mu: float
    sigma: float

    def cdf(self, x):
        if self.kind == "normal":
            return NormalDist(self.mu, self.sigma).cdf(x)
        return 0.0 if x <= 0 else NormalDist(self.mu, self.sigma).cdf(math.log(x))

    def quantile(self, p):
        p = min(max(p, 1e-9), 1 - 1e-9)
        q = NormalDist(self.mu, self.sigma).inv_cdf(p)
        return q if self.kind == "normal" else math.exp(q)


class MixtureDist:
    """Weighted mixture of component distributions. cdf is the weighted sum;
    quantile is found by bisection (cdf is monotone increasing)."""
    def __init__(self, comps):       # comps: list of (weight, Dist)
        self.comps = comps

    def cdf(self, x):
        return sum(w * d.cdf(x) for w, d in self.comps)

    def quantile(self, p):
        p = min(max(p, 1e-9), 1 - 1e-9)
        lo, hi = 1e-6, 200.0
        for _ in range(70):
            mid = (lo + hi) / 2
            if self.cdf(mid) < p:
                lo = mid
            else:
                hi = mid
        return (lo + hi) / 2


def _lognorm_from_median_cv(median, cv):
    return Dist("lognormal", math.log(median), math.sqrt(math.log(1 + cv * cv)))


def _strength_mix(p_train, un_ratio, un_cv, tr_ratio, tr_cv):
    """Mixture on the allometric score s = 1RM / BW^0.67, anchored at REF_BW.
    A ratio r (x BW) maps to a score s = r * REF_BW^(1-0.67)."""
    s_un = un_ratio * _REF_BW ** (1 - _ALLO)
    s_tr = tr_ratio * _REF_BW ** (1 - _ALLO)
    return MixtureDist([(1 - p_train, _lognorm_from_median_cv(s_un, un_cv)),
                        (p_train,      _lognorm_from_median_cv(s_tr, tr_cv))])


@dataclass(frozen=True)
class Standard:
    metric_id: str
    direction: int
    bodyweight_scaled: bool
    dist: object              # Dist | MixtureDist
    source: str
    provisional: bool = True
    # Health TARGET (e.g. body fat): at/below `ideal` the metric is optimal → Glory,
    # honest population percentile above it, with an exponential hockey-stick ramp
    # between ideal and ideal+ideal_band. Leaner-than-ideal never out-ranks ideal
    # (nor is penalised). None = ordinary lower/higher-is-better percentile.
    ideal: float | None = None
    ideal_band: float = 4.0


# ─── Standards: healthy young male, GENERAL population ─────────────────────
_REF_BW = 80.0
# Strength: untrained mass (grip-grounded CV 0.18) + trained tail (prevalence
# weight 0.22, trained-standard median/spread). Ratios are x bodyweight.
_GRIP_CV = 0.18
_P_TRAIN = 0.22
_TR_CV = 0.30

# Isolation lifts are ranked on ESTIMATED 1RM like every other lift (reps capped
# at 12, where Epley stays reliable) — so ranking rewards STRENGTH, not
# rep-grinding (12.5kg×8 out-ranks 10kg×12). Their standard anchors are 1RM ratios
# x bodyweight, the same form as the compounds. `_ISOLATION` is kept only to flag
# these as "estimate from a working set" in the UI (you rarely true-1RM a curl).
_ISOLATION = {"lateral_raise", "curl", "skull_crusher", "forearm_curl"}

def _S(mid, un_r, tr_r, note):
    return Standard(mid, +1, True,
                    _strength_mix(_P_TRAIN, un_r, _GRIP_CV, tr_r, _TR_CV), note)

STANDARDS = {
    # ── Strength compounds (grounded mixtures) ──
    "bench":    _S("bench",    0.50, 1.15, "mix: untrained 0.50x / trained 1.15x"),
    "squat":    _S("squat",    0.75, 1.60, "mix: untrained 0.75x / trained 1.60x"),
    "deadlift": _S("deadlift", 0.95, 2.00, "mix: untrained 0.95x / trained 2.00x"),
    "ohp":      _S("ohp",      0.32, 0.70, "mix: untrained 0.32x / trained 0.70x"),
    "pullup":   _S("pullup",   0.80, 1.50, "provisional"),
    "hip_thrust": _S("hip_thrust", 1.00, 2.50, "provisional"),
    "rdl":      _S("rdl",      0.80, 1.80, "provisional"),
    "calf_raise": _S("calf_raise", 0.80, 1.80, "provisional"),
    "crunch":   _S("crunch",   0.50, 1.00, "provisional"),
    # Isolation lifts — estimated-1RM ratios x bodyweight (same form as compounds).
    "lateral_raise": _S("lateral_raise", 0.10, 0.30, "est-1RM isolation, provisional"),
    "curl":          _S("curl",          0.20, 0.50, "est-1RM isolation, provisional"),
    "skull_crusher": _S("skull_crusher", 0.20, 0.50, "est-1RM isolation, provisional"),
    "forearm_curl":  _S("forearm_curl",  0.20, 0.40, "est-1RM isolation, provisional"),

    # ── Performance ──
    "vo2max":     Standard("vo2max", +1, False, Dist("normal", 48.0, 9.0),
                           "HUNT men 45.4±8.9, youth-nudged"),
    # Strict-form general-population holds cluster 20-60 s (fit adults 40-60+);
    # young-male median ~65 s. The old median of 80 ranked a solid 60 s hold
    # below the population middle.
    "plank":      Standard("plank", +1, False, Dist("lognormal", math.log(65), 0.5),
                           "strict plank hold sec; young-male median ~65 (genpop norms, "
                           "form-adjusted) — form-dependent"),
    "vert":       Standard("vert", +1, False, Dist("normal", 43.0, 11.0),
                           "CMJ-with-arms norms, genpop young male"),
    "run5k_kmh":  Standard("run5k_kmh", +1, False, Dist("lognormal", math.log(8.5), 0.28),
                           "5k speed vs GENERAL pop (selection-bias corrected) — FLAG"),
    # Common benchmarks: untrained men ~20-40 s, 60 s "good", 90 s+ strong →
    # young-male median ~50 s (a median of 60 made "good" the mere middle).
    "deadhang":   Standard("deadhang", +1, False, Dist("lognormal", math.log(50), 0.5),
                           "deadhang hold sec; young-male median ~50 — provisional"),
    # Sit-and-reach measured as CM PAST THE TOES (0 = fingertips touch toes;
    # negative = short). ACSM/YMCA-style norms put young men's median right
    # around the toes with a wide spread — the old N(15,5) said the median man
    # reaches 15 cm PAST his toes, so merely touching them ranked bottom 0.1%.
    "hamstring_mobility": Standard("hamstring_mobility", +1, False, Dist("normal", 2.0, 9.0),
                           "sit-and-reach, cm past toes (0 = touch); young-male median ~toes, "
                           "sd ~9 (ACSM/YMCA-style norms) — provisional"),
    "voice":      Standard("voice", -1, False, Dist("normal", 2.3, 0.8),
                           "Acoustic Voice Quality Index (lower better); healthy mean 2.3+-0.8 (Maryn), "
                           "vowel-only approximation - provisional"),
    # Photo/self-rating aesthetics - ranked on the measured 0-100 against ASSUMED,
    # uncalibrated distributions (no validated population data for the measured quantity).
    "skin":       Standard("skin", 1, False, Dist("normal", 62.0, 16.0),
                           "CV skin composite /100 - ASSUMED distribution, uncalibrated, provisional"),
    "oral":       Standard("oral", 1, False, Dist("normal", 60.0, 16.0),
                           "CV oral composite /100 - ASSUMED distribution, uncalibrated, provisional"),
    "hair":       Standard("hair", 1, False, Dist("normal", 230.0, 45.0),
                           "scalp hair density hairs/cm2 (higher better); young-male norm ~230+-45 "
                           "(trichoscopy) - measured from a macro photo, provisional"),
    "grooming":   Standard("grooming", 1, False, Dist("normal", 62.0, 18.0),
                           "grooming self-rating /100 - ASSUMED distribution (informed by ~5/10 crowd ratings), provisional"),
    "ear":        Standard("ear", 1, False, Dist("normal", 78.0, 14.0),
                           "hearing screening /100 (higher better) - ASSUMED distribution, uncalibrated, provisional"),
    "eye":        Standard("eye", -1, False, Dist("normal", 0.05, 0.15),
                           "visual acuity logMAR (lower better); general young-male presenting acuity "
                           "(median just below 20/20 from uncorrected error); best-corrected ~-0.14, provisional"),
    # Fitness-test norms (ACSM/Canadian PHE push-up tables) put young men's
    # median nearer ~25; the old mean of 35 sat at the "good/excellent" cut,
    # ranking an average performer Wood.
    "pushups":    Standard("pushups", +1, False, Dist("normal", 25.0, 12.0),
                           "push-ups in 60s; young-male median ~25 (ACSM/PHE-style norms), provisional"),
    "sprint_100m": Standard("sprint_100m", -1, False, Dist("normal", 15.5, 2.0),
                           "100m sprint seconds (lower better), young-male norms, provisional"),
    "body_fat_pct": Standard("body_fat_pct", -1, False, Dist("normal", 20.0, 6.0),
                           "health target: <=12% = Glory, population percentile above, provisional",
                           ideal=12.0),

    # ── Recovery ──
    "resting_hr": Standard("resting_hr", -1, False, Dist("normal", 70.0, 10.0),
                           "genpop RHR ~70±10 (lower better)"),
    "blood_pressure": Standard("blood_pressure", -1, False, Dist("normal", 122.0, 11.0),
                           "systolic BP mmHg (lower better); optimal <=105, genpop ~122+-11 - provisional",
                           ideal=105.0, provisional=True),
    "hrr":        Standard("hrr", 1, False, Dist("normal", 25.0, 10.0),
                           "1-min heart-rate recovery bpm (higher better); healthy ~25+-10 - provisional"),
    "hrv":        Standard("hrv", +1, False, Dist("lognormal", math.log(50), 0.5),
                           "HRV ms — method-dependent, FLAG"),
    "sleep_score": Standard("sleep_score", +1, False, Dist("normal", 77.0, 8.0),
                           "Fitbit/Google Health sleep score — most users 72-83 (IQR), provisional"),
}


# ─── Core engine ───────────────────────────────────────────────────────────
def _score(std, value, bodyweight):
    if std.bodyweight_scaled:
        if not bodyweight or bodyweight <= 0:
            raise ValueError(f"{std.metric_id} needs bodyweight-at-time")
        return value / (bodyweight ** _ALLO)
    return value


_IDEAL_GLORY_P = 0.9995  # capped just inside Glory (keeps rank_value < 9)


def _ideal_percentile(std, value):
    """Hockey-stick percentile for a health target (lower-is-better below the ideal)."""
    ideal, top = std.ideal, std.ideal + std.ideal_band
    if value <= ideal:
        return _IDEAL_GLORY_P  # optimal → top tier, no reward below
    p_nat = 1.0 - std.dist.cdf(value)  # honest population percentile above ideal
    near = min(max((top - value) / (top - ideal), 0.0), 1.0)
    p = p_nat + (1.0 - p_nat) * near ** 3  # cubic = accelerating climb to Glory
    return min(p, _IDEAL_GLORY_P)


def percentile(metric_id, value, bodyweight=None):
    std = STANDARDS[metric_id]
    if std.ideal is not None:
        return _ideal_percentile(std, value)
    below = std.dist.cdf(_score(std, value, bodyweight))
    P = below if std.direction == +1 else 1.0 - below
    return min(max(P, 0.0), 1.0)


def _tier_idx(P):
    idx = 0
    for i, e in enumerate(TIER_ENTRY_P):
        if P >= e:
            idx = i
    return idx


def _rank_value_from_P(P):
    idx = _tier_idx(P)
    lo = TIER_ENTRY_P[idx]
    hi = TIER_ENTRY_P[idx + 1] if idx + 1 < len(TIER_ENTRY_P) else 1.0
    frac = 0.0 if hi <= lo else min(max((P - lo) / (hi - lo), 0.0), 1.0)
    return idx + frac


def rank_value(metric_id, value, bodyweight=None):
    return _rank_value_from_P(percentile(metric_id, value, bodyweight))


def tier_of(metric_id, value, bodyweight=None):
    P = percentile(metric_id, value, bodyweight)
    rv = _rank_value_from_P(P)
    idx = min(int(rv), len(TIERS) - 1)  # rv hits 9.0 at P=1.0 → keep index in range
    return {"tier": TIERS[idx], "sub": SUB[min(int((rv - idx) * 3), 2)],
            "top_pct": (1 - P) * 100, "percentile": P * 100, "rank_value": rv}


def threshold(metric_id, tier, bodyweight=None):
    std = STANDARDS[metric_id]
    P_entry = TIER_ENTRY_P[TIERS.index(tier)]
    if std.ideal is not None:
        # Numerically invert the hockey-stick (percentile is monotone-decreasing).
        lo, hi = 0.0, 60.0
        for _ in range(60):
            mid = (lo + hi) / 2
            if _ideal_percentile(std, mid) >= P_entry:
                lo = mid
            else:
                hi = mid
        return lo
    cdf_p = P_entry if std.direction == +1 else 1.0 - P_entry
    x = std.dist.quantile(cdf_p)
    return x * (bodyweight ** _ALLO) if std.bodyweight_scaled else x


@dataclass
class Log:
    metric_id: str
    value: float
    bodyweight: float | None = None
    ts: str | None = None


def score_log(log: Log):
    return tier_of(log.metric_id, log.value, log.bodyweight)


def overall(logs):
    zs = []
    for log in logs:
        if log.metric_id not in STANDARDS:
            continue
        P = min(max(percentile(log.metric_id, log.value, log.bodyweight), 1e-6), 1 - 1e-6)
        zs.append(_Z.inv_cdf(P))
    return _result_from_zs(zs)


# Overall weights each category by whole-person health importance (not metric count).
# Keep in sync with rank_engine.dart `categoryWeights`.
CATEGORY_WEIGHTS = {
    "performance": 0.30,
    "strength": 0.28,
    "recovery": 0.27,
    "aesthetics": 0.15,
}


def overall_by_category(logs_by_category):
    """Overall rank blending CATEGORIES by CATEGORY_WEIGHTS (not per-metric), re-normalised
    over whichever categories have data — so metric count doesn't bias the headline."""
    acc = wsum = 0.0
    for cat, logs in logs_by_category.items():
        zs = []
        for log in logs:
            if log.metric_id not in STANDARDS:
                continue
            P = min(max(percentile(log.metric_id, log.value, log.bodyweight), 1e-6), 1 - 1e-6)
            zs.append(_Z.inv_cdf(P))
        if not zs:
            continue
        cat_z = sum(zs) / len(zs)
        w = CATEGORY_WEIGHTS.get(cat, 1.0)
        acc += w * cat_z
        wsum += w
    if wsum == 0:
        return {"tier": "Wood", "sub": "I", "top_pct": 99.9, "rank_value": 0.0}
    return _result_from_zbar(acc / wsum)


def _result_from_zs(zs):
    if not zs:
        return {"tier": "Wood", "sub": "I", "top_pct": 99.9, "rank_value": 0.0}
    return _result_from_zbar(sum(zs) / len(zs))


def _result_from_zbar(zbar):
    Pbar = _Z.cdf(zbar)
    rv = _rank_value_from_P(Pbar)
    idx = min(int(rv), len(TIERS) - 1)
    return {"tier": TIERS[idx], "sub": SUB[min(int((rv - idx) * 3), 2)],
            "top_pct": (1 - Pbar) * 100, "rank_value": rv}


def est_1rm(weight, reps):
    if reps <= 0 or weight <= 0:
        return 0.0
    if reps == 1:
        return weight
    r = min(reps, 12)
    return round(((weight * (1 + r / 30)) +
                  (weight / (1.0278 - 0.0278 * r)) +
                  ((100 * weight) / (101.3 - 2.67123 * r))) / 3, 2)


def strength_value(metric_id, weight, reps):
    """Canonical strength quantity for ranking: estimated 1RM for EVERY lift,
    accessories included (Epley averaged, reps capped at 12). Ranking on est-1RM
    rewards strength over rep-grinding — 12.5kg×8 out-ranks 10kg×12."""
    return est_1rm(weight, reps)


# ═══ SELF-TEST + BELIEVABILITY ═════════════════════════════════════════════
def run_self_tests():
    print("STRUCTURAL TESTS")
    print("-" * 64)
    bw = 80
    ok = all(percentile("bench", w, bw) <= percentile("bench", w + 5, bw)
             for w in range(20, 200, 5))
    print(f"  [{'PASS' if ok else 'FAIL'}] bench percentile monotonic in weight")

    l1, l2 = 4.0 * 65 ** _ALLO, 4.0 * 100 ** _ALLO
    p1, p2 = percentile("bench", l1, 65), percentile("bench", l2, 100)
    print(f"  [{'PASS' if abs(p1-p2) < 1e-9 else 'FAIL'}] equal allometric score "
          f"=> equal percentile ({p1*100:.2f}% vs {p2*100:.2f}%)")

    ok = percentile("resting_hr", 50) > percentile("resting_hr", 80)
    print(f"  [{'PASS' if ok else 'FAIL'}] resting HR 50 ranks above 80")

    t = threshold("bench", "Diamond", bw)
    landed = tier_of("bench", t, bw)
    print(f"  [{'PASS' if abs(landed['top_pct']-10.0) < 0.5 else 'FAIL'}] derived "
          f"Diamond bench threshold ({t:.1f}kg) lands at top {landed['top_pct']:.1f}%")

    correct = score_log(Log("bench", 100, 75))
    wrong = tier_of("bench", 100, 90)
    print(f"  [{'PASS' if abs(correct['top_pct']-wrong['top_pct']) > 0.5 else 'FAIL'}] "
          f"past lift keeps snapshot rank ({correct['tier']} {correct['sub']}, "
          f"top {correct['top_pct']:.1f}%) not current-BW rank ({wrong['tier']} "
          f"{wrong['sub']}, top {wrong['top_pct']:.1f}%)")
    print()


def believability():
    print("BELIEVABILITY — mixture-modelled strength (75 kg young male)")
    print("=" * 70)
    bw = 75
    for lift in ["bench", "squat", "deadlift", "ohp"]:
        med = threshold(lift, "Bronze", bw)  # not median, just to anchor display
        print(f"\n{lift.upper()}  (population median "
              f"{STANDARDS[lift].dist.quantile(0.5)*bw**_ALLO:.0f} kg)")
        for r in [0.5, 0.75, 1.0, 1.5, 2.0, 2.5]:
            t = tier_of(lift, r * bw, bw)
            print(f"  {r:.2f}x BW ({r*bw:5.1f} kg) -> {t['tier']:<9}{t['sub']:<3} "
                  f"top {t['top_pct']:5.1f}%")
    print("\nDERIVED bench tier ladder @ 75 kg BW")
    for tier in ["Bronze","Silver","Gold","Platinum","Diamond","Champion","Titan"]:
        kg = threshold("bench", tier, bw)
        print(f"  {tier:<9} {kg:5.1f} kg ({kg/bw:.2f}x)  [top {TIER_TOP_PCT[tier]:.0f}%]")
    print("=" * 70)


if __name__ == "__main__":
    run_self_tests()
    believability()
