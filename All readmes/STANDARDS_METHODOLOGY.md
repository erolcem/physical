# Physical — Standards Methodology (v0.4)

How every ranked metric's population distribution is sourced and modelled. This
is the reference for *why* the numbers in `physical_rank_engine.py` are what they
are, so they can be defended, audited, and tuned. Reference population: **healthy
males ~18–30 (general population, not just people who train).**

Governing rule: **a rank is only honest if a defensible distribution sits behind
it.** Where the data is weak, we say so and flag the metric `provisional`.

---

## 1. The core mechanism (all metrics)

1. Normalise the raw input to a comparable score `x` (strength: estimate 1RM,
   then divide by `bodyweight^0.67`; everything else: the value itself).
2. Read the percentile straight off the metric's population distribution:
   `P = CDF(x)`, adjusted by a `direction` flag for lower-is-better metrics.
3. Derive the eight tier thresholds as quantiles of that distribution. Thresholds
   are **outputs**, never hand-typed.

Tiers map to fixed top-percentile cutoffs: Bronze 80%, Silver 60%, Gold 40%,
Platinum 20%, Diamond 10%, Champion 3%, Titan 1%, Glory <0.1% (uncapped).

---

## 2. Strength — modelled, because it cannot be looked up

### The problem
Public "strength standards" (Strength Level, ExRx, etc.) describe **people who
train**, because you cannot log a lift you have never attempted. Normative work
(NHANES handgrip; Bohannon muscle-strength norms) shows the median adult's
maximal strength is **below** what those sites label "untrained". So lifting-app
percentiles answer "how do I compare to other lifters?", not "how do I compare to
the population?" — which is what an honest, motivating rank needs.

### Why "full population" (Erol's call) is the right reference
Ranking against trained lifters would make a beginner feel locked out of an elite
club. Against the **whole** young-male population, modest-but-real achievements
land high (benching your bodyweight ≈ top ~15–20%), which is both accurate and
motivating. Consistency also requires one reference population across *all*
metrics — strength can't be "vs lifters" while VO₂max is "vs everyone".

### How the distribution is built — two-component mixture (v0.3)
The general young-male strength distribution is dominated by **training status**.
Whole-population strength is unimodal and modestly spread; the long right tail in
bench/squat is created by *training*, not by biological variation. So each lift is
modelled as a **mixture of two lognormals on the allometric score** `s = 1RM/BW^0.67`:

- **Untrained component** (weight `1 − p_train`). The majority who don't train
  structurally. Centre is low (per-lift, below the lifting-app "untrained" mark);
  spread `CV ≈ 0.18`, taken from whole-population **grip-strength norms** — young
  men average ~50 kg dominant-hand grip (49.7 kg for men 25–29 in the NIH-Toolbox
  normative study), and grip is **normally distributed within each age band**,
  giving the untrained mass its modest, unimodal spread.
- **Trained component** (weight `p_train ≈ 0.22`). The slice doing structured
  barbell work that yields a real, progressing 1RM. CDC/NHIS 2020: **44.5%** of men
  18–44 met the muscle-strengthening guideline (which counts push-ups/sit-ups), so
  the *serious-lifting* subset is ~20–25%. Centre and spread (`CV ≈ 0.30`) come from
  trained standards (intermediate ≈ bodyweight-plus bench; tail reaches 2×+ BW).

Mixture parameters (ratios are × bodyweight, at reference BW 80 kg):

| Lift | Untrained centre | Trained centre | Resulting median | Resulting tiers |
|---|---|---|---|---|
| Bench | 0.50× BW | 1.15× BW | ~0.54× BW | 1×BW = top 16%, 2×BW = top 0.8% |
| Squat | 0.75× BW | 1.60× BW | ~0.82× BW | 1.5×BW = top 14%, 2.5×BW = top 1.6% |
| Deadlift | 0.95× BW | 2.00× BW | ~1.03× BW | 2×BW = top 12%, 2.5×BW = top 5% |
| OHP | 0.32× BW | 0.70× BW | ~0.35× BW | 1×BW = top 3%, 1.5×BW = top 0.1% |

Built in `_strength_mix()` / `MixtureDist` (cdf = weighted sum; quantile by
bisection). Retuning = edit the centres / weight / CVs; the engine is untouched.
The mid/upper ranks match the previous single-lognormal cut (bench bodyweight
moved 15.9% → 15.6%), so anything already validated is preserved; the **low end is
now grounded** rather than extrapolated.

### Allometric scaling (`BW^0.67`)
Cross-sectional strength scales ~`BW^(2/3)` (surface-law). Dividing by `BW^0.67`
makes the score size-fair: the *average* man of any bodyweight has the same
score. It sits between simple ratio (over-credits light lifters) and absolute kg
(over-credits heavy lifters). Exponent is a tunable constant (`_ALLO`).

### Residual weak spot
The **untrained component's centre** is still an estimate — untrained 1RMs are
barely measured directly, so grip data constrains the *spread* but not the exact
per-lift mean. Tightening it (e.g. from any direct untrained-1RM study, or a
grip→press regression) is the remaining refinement; the structure is now correct.

### Isolation lifts (curls, lateral raises, etc.)
Estimated 1RM is unreliable for these and few train them to a true max, so they
are ranked on **rep-volume-at-load** — the working-set volume `weight × reps`,
allometrically scaled like any strength score — instead of a 1RM-derived rank.

The population anchors reuse the same untrained/trained mixture, derived from the
prior 1RM ratios × a representative working set (`_WORKING_SET = 8.4`, i.e. ~12
reps at ~70 % 1RM, since `vol = 0.70·1RM × 12 ≈ 1RM × 8.4`). So a lifter doing a
standard working set lands at the same percentile as before, while genuine rep/
load variation (20 light reps vs 8 heavy ones) is now scored honestly rather than
forced through a misleading 1RM estimate. Still provisional pending isolation
volume-load population data. Applies to `lateral_raise`, `curl`, `skull_crusher`,
`forearm_curl`; both engines (`physical_rank_engine.py`, `rank_engine.dart`) share
the `strength_value`/`strengthValue` dispatcher and identical anchors.

---

## 3. Bodyweight-at-time (a correctness rule, not an option)

A strength lift is scored against the bodyweight the lifter was **when they did
it**, snapshotted on the log and immutable. Rationale:

- Scoring against *current* bodyweight would silently **demote every past lift**
  when you gain weight (same bar, bigger `BW^0.67` denominator) and inflate
  history when you lose weight. Ranks you earned must be permanent.
- Correct incentive: getting **leaner at the same load** raises the score of your
  **new** lifts (better relative strength) while old ranks stay exactly put.

Implementation: each strength `sample` carries `bodyweight_at_ts` (auto-filled
from the latest bodyweight at log time, user-editable). Ranking — current,
historical, and charted — always uses that snapshot. A strength log with no known
bodyweight prompts for one once.

---

## 4. Non-strength metrics

| Metric | Distribution | Source | Confidence |
|---|---|---|---|
| VO₂max | normal(48, 9) | HUNT: men 45.4 ± 8.9 ml/kg/min, youth-nudged | High |
| Resting HR (↓ better) | normal(70, 10), dir −1 | general adult RHR ~70 ± 10 | Medium-High |
| Vertical jump | normal(43, 11) | CMJ-with-arms norms (untrained ~40–50 cm; method-sensitive) | Medium |
| Plank | lognormal(ln 80, 0.5) | WKU normative study (males median ~110 s, active-biased → ~80 s genpop); **form-dependent** | Medium-Low |
| 5k speed | lognormal(ln 8.5, 0.28) | **selection-bias corrected** — race data is runners-only; general young-male median is a slow jog ~8.5 km/h, sub-30 min ≈ top 25% | Low — FLAG |
| HRV | lognormal(ln 50, 0.5) | method-dependent (device/time/posture) | Low — FLAG |

**5k is the strength problem again:** published 5k data is self-selected runners,
not the population. Against *all* young men (most of whom don't run a 5k), being
able to run one at all is already above median; we set the population median to a
slow jog and let the runner range form the upper tiers. Flagged provisional.

VO₂max and resting HR have real general-population data and are the most trusted.
HRV is the shakiest — its distribution depends heavily on measurement method, so
it must document its measurement assumption or be treated as tracked-leaning.

---

## 5. Versioning & retuning

Standards are **versioned** (`bench@v1`, etc.). Because samples are immutable and
ranks are derived, recomputing everyone under `@v2` is a batch job, not a
migration. The believability check (do real lifts produce believable percentiles?)
is re-run on every standards change before it ships.

---

## 6. Refinement backlog (priority order)

1. ~~General-population strength medians → two-component mixture per lift.~~
   **DONE (v0.3)** — grip-grounded untrained mass + prevalence-weighted trained
   tail. Residual: tighten the untrained centre from a direct untrained-1RM source.
2. **Per-lift trained anchors** — replace round-number ratios with values read off
   trained datasets at the prevalence-implied percentile.
3. ~~Performance metrics (plank, vert, 5k).~~ **DONE (v0.4)** — vert (CMJ norms),
   plank (WKU normative study, form-adjusted), 5k (selection-bias corrected vs
   general pop). Residual: mobility unmodelled; 5k & plank stay method-sensitive.
4. **HRV measurement model** — pin the method (e.g. morning RMSSD) and source a
   matching distribution, or demote to tracked.
5. **Allometric exponent** — fit `_ALLO` to the adopted dataset instead of 0.67.
