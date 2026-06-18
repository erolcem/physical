# Physical — Standards Methodology (v0.2)

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

### How the distribution is built
The general young-male strength distribution is dominated by **training status**,
not the biological spread of untrained strength. So we anchor it from prevalence
+ the trained tail, rather than a (non-existent) general-population 1RM dataset:

- **Training prevalence (anchor for where trained levels sit in percentile terms).**
  CDC/NHIS 2020: **44.5%** of men aged 18–44 met the muscle-strengthening
  guideline — but that counts push-ups/sit-ups. The slice doing structured
  barbell work that yields a real, progressing 1RM is smaller, ~15–25%. ACSM
  reviews put ~30% of all adults doing *any* muscle-strengthening ≥2×/week and
  ~60% doing none.
- **Trained tail (anchor for absolute load).** Established trained levels
  (≈ bodyweight bench = a serious-trainee milestone; ≈ 2× bodyweight = near
  competitive) provide the absolute kg at the high percentiles.

We fit a **lognormal on the allometric score** `s = 1RM / BW^0.67` through two
transparent anchors per lift, expressed at a reference bodyweight of 80 kg:

| Lift | Low anchor (≈ top 15%) | High anchor (≈ top 1%) | Implied median | Confidence |
|---|---|---|---|---|
| Bench | 1.00× BW | 2.00× BW | ~0.55× BW | tail solid, median soft |
| Squat | 1.40× BW | 2.50× BW | ~0.8× BW | tail solid, median soft |
| Deadlift | 1.75× BW | 3.00× BW | ~1.0× BW | tail solid, median soft |
| OHP | 0.60× BW | 1.10× BW | ~0.35× BW | tail solid, median soft |

The fit is in `fit_lognormal_from_anchors()`, so a standard is *defined by its
anchors* — to retune, edit the anchor, not the engine.

### Allometric scaling (`BW^0.67`)
Cross-sectional strength scales ~`BW^(2/3)` (surface-law). Dividing by `BW^0.67`
makes the score size-fair: the *average* man of any bodyweight has the same
score. It sits between simple ratio (over-credits light lifters) and absolute kg
(over-credits heavy lifters). Exponent is a tunable constant (`_ALLO`).

### Known weak spot
The **median** of each lift is the least-certain number (it's an output of the
tail anchors, and untrained 1RMs are barely measured). **Refinement plan:** model
the untrained baseline from NHANES handgrip + Bohannon norms and the trained tail
separately, then fit a proper two-component mixture. Until then: `provisional`.

### Isolation lifts (curls, lateral raises, etc.)
Estimated 1RM is unreliable for these and few train them to a true max. They move
to a **rep-volume-at-load** model rather than a 1RM-derived rank (TODO).

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
| VO₂max | normal(48, 9) | HUNT (Loe et al.): men 45.4 ± 8.9 ml/kg/min; nudged up for youth | High |
| Resting HR (↓ better) | normal(70, 10), direction −1 | general adult RHR ~70 ± 10 | Medium-High |
| Plank | lognormal(ln 75, 0.55) | max-hold norms, genpop | Provisional |
| Vertical jump | normal(41, 12) | young-male jump norms | Provisional |
| 5k speed | normal(11.0, 2.3) km/h | recreational/genpop (~27 min median) | Provisional |
| HRV | lognormal(ln 50, 0.5) | **method-dependent** (device/time/posture) | Low — FLAG |

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

1. **General-population strength medians** — NHANES handgrip + Bohannon → two-
   component (untrained ∪ trained) mixture per lift. *Highest priority.*
2. **Per-lift trained anchors** — replace round-number ratios with values read off
   trained datasets at the prevalence-implied percentile.
3. **Performance metrics** (plank, vert, 5k, mobility) — swap provisional norms for
   cited fitness-test datasets (ACSM / military / academic).
4. **HRV measurement model** — pin the method (e.g. morning RMSSD) and source a
   matching distribution, or demote to tracked.
5. **Allometric exponent** — fit `_ALLO` to the adopted dataset instead of 0.67.
