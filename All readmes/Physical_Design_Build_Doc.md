# Physical — Design & Build Document

**Version:** 0.1 (working draft)
**Authors:** Erol Cemiloglu (product + primary dev), Semih Cemiloglu (backend / integration / data), with Claude (design + code partner)
**Status:** Pre-build. This is the reference we build from. It is intentionally detailed end-to-end, but we build one phase at a time.

---

## 0. How to read this document

This is a living design doc. Sections 1–5 describe *what* the finished product is and *how its parts work* (the model). Section 6 is the *build order*. Section 7 tracks open decisions. The appendix holds the precise rank-engine spec and the metric registry.

The guiding rule everywhere: **a displayed rank or percentile must be honest, or the gamification collapses.** This is the lesson learned from the prototype, where hand-picked, bodyweight-blind thresholds made the ranks feel arbitrary. Every design choice below is downstream of that rule.

---

## 1. Product vision & first principles

**One line.** Physical measures every trainable dimension of a (for v1) healthy young male, grounds each one in an *honest population percentile*, turns that into a visible rank on a body graph, and uses an AI coach to drive iterative improvement.

**The differentiator.** Logging apps are commodity. Google Health already does data screens well. What Physical does that they don't is convert raw numbers into *meaningful, population-grounded standing* — "Diamond, top 9% for your bodyweight" instead of "92.5 kg". The body graph + rank system is the product. Everything else supports it.

**First principles:**

1. **Rank honesty = immersion.** A rank is only allowed to exist when there is a defensible population distribution behind it. No guessed thresholds. No fabricated percentiles.
2. **Size-fair by default.** Strength is judged relative to bodyweight, not in absolute kilograms.
3. **Three data tiers** (see §2). Not everything is ranked; some things are tracked; some things are pure context.
4. **Modular sources.** The app reads one canonical data model; where a number came from (manual, HealthKit, Fitbit) is an implementation detail behind an adapter.
5. **Coach, not clinician.** The AI motivates and educates. It never diagnoses, and the product is framed and disclaimed to stay clear of the medical-device line.
6. **Wellbeing over engagement.** We do not rank appearance against a "perfection" ceiling, and we do not optimise for compulsive use.

**v1 scope boundary.** Reference population = healthy males, ~18–30. Female standards, age banding, and youth/masters cohorts are explicitly out of scope for v1 and noted as a future distribution-set, not a re-architecture.

---

## 2. The data model (the spine)

Every metric in the app belongs to exactly one **tier**, which determines where it appears and whether it is ranked.

| Tier | Ranked? | Surfaced where | Examples | Purpose |
|---|---|---|---|---|
| **Ranked** | Yes | Body graph + ranks + overall/category score | bench/squat/etc. 1RM, VO₂max, plank, 5k, HRV, sleep score, vert, mobility | The gamified core |
| **Tracked (foreground)** | No | Graphs page (as plain scored series) | skin, oral, hair density, grooming, voice | User actively improves; AI reads; no population rank |
| **Background** | No | Graphs page (optional) + AI context only | resting HR stream, skin temp variation, cardio load, steps, AZM, sleep sub-metrics, total energy burned, food logs | Ambient context the coach reasons over |

This replaces the prototype's implicit two-way split and, crucially, removes two hacks:

- **Direction is explicit.** Each metric declares `direction: +1` (higher is better) or `-1` (lower is better). This kills the `100 − bpm` encoding trick used for resting heart rate and makes body-fat %, 5k time, etc. first-class without contortions.
- **Aesthetics are unranked by design.** They have no defensible population distribution and ranking appearance against "perfection" is a wellbeing risk. They live as tracked scores you can graph and improve, and the coach uses them — but they never get a tier or feed the overall score.

### 2.1 Metric registry

A single declarative registry defines every metric. Conceptually each entry is:

```
{
  id:               "bench"            // stable key
  label:            "Chest (Bench)"
  tier:             "ranked"           // ranked | tracked | background
  category:         "strength"         // strength | performance | recovery | aesthetics | context
  unit:             "kg"
  direction:        +1                 // +1 higher-better, -1 lower-better
  bodyweightScaled: true               // strength lifts only
  input:            "weight_reps"       // weight_reps | score | duration | distance | auto
  bodygraph:        ["F-chest-l","F-chest-r"]   // SVG element ids, ranked tier only
  standardsRef:     "bench@v1"         // points into the standards config (§3)
  sources:          ["manual"]          // adapters that can write this metric
}
```

The rest of the app is generated from this registry — exactly as the prototype's `MUSCLES` array already drives the UI. We are keeping that pattern; we are just enriching the entries and removing the parts that encoded ranking logic by hand.

### 2.2 Canonical sample schema (the contract)

All measured data, regardless of source, normalises into **one** time-series shape. Nothing in the app reads a source-native format directly.

```
sample {
  user_id        uuid
  metric_id      text        -> metric registry
  ts             timestamptz // event time, timezone-aware
  value          double      // canonical unit (always SI/kg/seconds per registry)
  raw            jsonb       // original payload for traceability (e.g. {weight, reps, unit})
  source         text        // manual | healthkit | fitbit | healthconnect | ...
  source_id      text        // source's own record id, for idempotent re-sync
  ingested_at    timestamptz
}
```

Three rules make this robust, and they come directly from how the real APIs behave:

1. **Provenance is mandatory.** Every sample knows its source. The new Fitbit/Google Health API explicitly exposes both a *reconciled* stream and a *raw device/manual* stream; we store both and tag them.
2. **Deduplication via `(metric_id, source, source_id)`.** Re-syncing the same Fitbit day must not double-count. Manual logs get a generated `source_id`.
3. **Precedence resolver.** When two sources report the same metric for the same window (phone HR vs Fitbit HR), a per-metric precedence list decides the winner for display and ranking. The losing samples are retained, not discarded.

On Postgres + TimescaleDB this is a hypertable on `ts`, which is the natural fit for this access pattern (range scans over time per user/metric) and is already in Semih's toolbox from the trading stack.

### 2.3 Profile

```
profile { user_id, sex, age (or age_band), height_cm, units_pref }
```

Bodyweight is **not** a static profile field and **not** a ranked metric. It is a normal tracked time-series (`metric_id = "bodyweight"`) so it can change over time — and it is the denominator that scales every strength rank (§3.2). This single change fixes the prototype's "heavier = better" `mass` rank, which was a clear immersion-breaker.

**Bodyweight-at-time (correctness rule).** A strength lift is scored against the bodyweight the lifter was *when they did it* — snapshotted onto the log (`bodyweight_at_ts`, auto-filled from the latest bodyweight, user-editable) and immutable thereafter. Scoring against *current* bodyweight would silently demote every past lift when you gain weight and inflate history when you lose it; ranks you earned must be permanent. The correct incentive falls out naturally: getting leaner at the same load raises the score of your *new* lifts while old ranks stay put. Current, historical, and charted ranks all use the per-lift snapshot.

---

## 3. The ranking engine (corrected)

### 3.1 What was wrong, briefly

The prototype keyed ranks to **absolute-kg thresholds chosen by feel**, then *linearly interpolated* a percentile between them. Three consequences: a number meant different things for different bodyweights; the percentile labels didn't match reality; and lower-is-better metrics needed encoding hacks. The fix is to invert the whole flow.

### 3.2 The corrected flow

For each ranked metric we define a **population distribution** for the reference cohort, then read the user's standing *off that distribution*. Thresholds become **outputs**, not inputs.

**Step 1 — normalise the raw input to a comparable score `x`.**
- Strength lifts: estimate 1RM from the logged set (Epley/Brzycki/Lander blend is fine as a placeholder for low reps; for isolation lifts we use a rep-volume-at-load model instead of a dubious 1RM — flagged per metric). Then **allometric-scale**: `x = 1RM / bodyweight^0.67`, where `bodyweight` is the lifter's weight *at the time of that lift* (§2.3), not their current weight. Cross-sectional strength scales roughly with `BW^(2/3)`, so dividing by `BW^0.67` gives a size-fair score that doesn't over-credit very light or penalise heavy lifters.
- Score metrics (VO₂max, HRV, plank, 5k speed, sleep score, etc.): `x` = the value itself.

**Step 2 — convert `x` to a population percentile via the metric's distribution.**
- Represent each metric's distribution as either *parametric* (normal, or log-normal for skewed metrics — store μ, σ) or *empirical* (a monotone value→percentile curve fitted to a real dataset's published quantiles).
- `P = CDF(x)` = fraction of the population at or below `x`.
- Apply direction: higher-is-better reports "top `(1 − P)`"; lower-is-better (`direction = −1`) uses `P′ = 1 − CDF(x)` first. Direction is a metric property — no encoding tricks.

**Step 3 — map percentile to tier.** The eight tiers correspond to fixed top-percentile cutoffs (this preserves Erol's original intent):

| Tier | Wood | Bronze | Silver | Gold | Platinum | Diamond | Champion | Titan | Glory |
|---|---|---|---|---|---|---|---|---|---|
| Top % entry | (below Bronze) | 80% | 60% | 40% | 20% | 10% | 3% | 1% | <0.1%, uncapped |

The **threshold in real units** for each tier is now derived: `tierThreshold = Quantile(1 − topPct/100)`. So Diamond-for-bench is "whatever bench (bodyweight-scaled) sits at the 90th percentile", computed from the distribution — never typed in by hand.

**Step 4 — continuous position & subranks.** The within-tier fraction is computed in **percentile space** (not raw-unit space), so the progress bar advances evenly and always agrees with the displayed percentile. Subranks I/II/III are the three equal percentile-thirds of the tier band. The continuous `rankValue = tierIndex + fraction` remains the single canonical number the body graph, charts, and overall score all read — same architecture as the prototype's `preciseRankValue`, just fed by honest inputs.

**Glory tier.** Beyond the 1% Titan cutoff, the upper tail extends with no ceiling (e.g. position by how many SDs / how far down the percentile tail). This gives the "endless runway" the doc asked for without inventing a fake cap.

### 3.3 Overall & category scores

The prototype averaged raw `preciseRankValue`s. That mixes tiers of unequal width. We instead **average in percentile (or normal-quantile / z) space** across the metrics in a group, then map the average back to a tier for display. This is more principled and keeps category scores comparable.

### 3.4 Why this is *both* realistic and gamified

Because tiers are fixed *population fractions*, the climb gets exponentially harder near the top (20% → 10% → 3% → 1% are rarer and rarer). That is exactly the satisfying RPG difficulty curve — and it is honest, because it's literally how rare that performance is. The "realistic AND gamified" goal is served by the *same* mechanism, not a trade-off between them.

### 3.5 Standards as versioned, tunable config (the research workstream)

The distributions live in a declarative **standards config**, separate from code, and **versioned**:

```
bench@v1 {
  metric:        "bench"
  direction:     +1
  bodyweightScaled: true
  distribution:  { type: "lognormal", mu: ..., sigma: ... }   // on the BW^0.67-scaled score
  source:        "Citation / dataset + cohort description"
  provisional:   true
}
```

Tuning a standard = editing config and bumping a version; no engine code changes. Because samples are immutable and ranks are derived, we can recompute everyone's ranks under `@v2` when a standard improves.

**Per-metric data sourcing (v1 plan).** Honesty here is per-metric, because the data quality differs:

| Metric | Best-available source for v1 distribution | Confidence |
|---|---|---|
| VO₂max | Published normative tables (e.g. ACSM/Cooper-style age-banded norms) | High |
| 5k speed, plank, vertical jump, sit-and-reach | Fitness-test normative datasets (military / ACSM / academic) | Medium–High |
| Resting HR, HRV | Wearable-population studies (method-dependent — document the measurement assumption) | Medium |
| Sleep score | Vendor score is already 0–100 normative-ish; treat as tracked-leaning, document it | Medium |
| Barbell lifts (bench/squat/DL/OHP/etc.) | Only *trained-population* data exists publicly; we must (a) label the cohort honestly as "trained lifters", or (b) shift toward general-population strength proxies where available | **Low — flagged** |

Every v1 standard ships `provisional: true` with its cohort documented, so we never silently claim a general-population percentile we can't back. This per-metric honesty *is* the immersion guarantee.

### 3.6 Engine API (ports straight to Dart)

The engine stays a **pure, deterministic, no-I/O package** — exactly the property the prototype's `rank.js` already has, which is why it ports cleanly. Core surface:

```
percentile(metricId, x, profile) -> 0..1
rankValue(metricId, x, profile)  -> continuous tier+fraction
tierOf(metricId, x, profile)     -> {tier, sub, topPct}
threshold(metricId, tier, profile) -> value in real units (derived)
overall(samplesByMetric, profile) -> {rankValue, topPct}  // percentile-space avg
```

It is unit-tested exhaustively (golden cases per metric, monotonicity, boundary behaviour, bodyweight invariance checks). This is the one component where correctness is non-negotiable, so it gets the heaviest test coverage in the project.

---

## 4. Architecture & tech stack

### 4.1 Stack summary

| Layer | Choice | Why |
|---|---|---|
| Client (iOS first, Android later) | **Flutter / Dart** | One codebase for both platforms; excellent custom 2D rendering (CustomPainter) for the body graph and badges; HealthKit via the `health` plugin; the JS rank engine ports cleanly to a pure Dart package |
| Rank engine | **Pure Dart package** | Deterministic, shareable, exhaustively testable; mirrors the prototype's pure `rank.js` |
| Backend API | **Python + FastAPI** | Both devs know Python; fast to build cleanly; good async story for adapters/LLM calls |
| Datastore | **PostgreSQL + TimescaleDB** | Purpose-built for the time-series sample table; already in Semih's toolbox |
| AI coach service | **FastAPI service + local/cloud LLM routing** | Local Ollama models for cheap/private calls; cloud model for heavy reasoning, with PII scrubbing before egress |

### 4.2 Data-source adapters (the modular boundary)

Modularity does **not** come from "one database" — it comes from the **canonical schema + an adapter per source** (the anti-corruption / canonical-data-model pattern Semih works with daily). Each adapter's only job is: read its source, translate to canonical `sample`s, write them. The app and engine read only canonical data and never know the source.

A wrinkle the platform privacy models force on us:

- **On-device adapters** (HealthKit on iOS; Health Connect on Android later): the OS only exposes this data *on the device*. So the Flutter app reads it locally, normalises to canonical, and syncs samples **up** to the backend.
- **Cloud adapter** (Fitbit via the Google Health API): a true server-side cloud-to-cloud pull, normalised server-side.
- **Manual logs**: written straight to canonical from the app.

This split (on-device vs server-side adapters, same canonical target) is baked into the design rather than discovered later.

> **API timing note:** Google Fit APIs are deprecated (end of service late 2026; new signups already closed), and the legacy Fitbit Web API is migrating to the Google Health API (Google OAuth, mandatory re-consent) through 2026. So the integration targets are **HealthKit (iOS), Health Connect (Android), and the Google Health API (Fitbit)** — three adapters, not "the Google Health API" as a single thing. Phase 1 needs none of them (manual logging only), which is why integrations are deliberately a later phase.

### 4.3 System shape

```
            ┌──────────────── Flutter app (iOS) ────────────────┐
            │  UI (body graph, graphs, habits, coach, profile)  │
            │  Dart rank engine (pure)                          │
            │  On-device adapters: HealthKit  → canonical       │
            │  local cache / offline-first                      │
            └───────────────┬───────────────────────────────────┘
                            │  sync (canonical samples) / REST
            ┌───────────────▼───────────────────────────────────┐
            │  FastAPI backend                                  │
            │   • canonical sample store (Postgres/TimescaleDB) │
            │   • standards config (versioned)                  │
            │   • precedence/dedup resolver                     │
            │   • cloud adapter: Google Health API (Fitbit)     │
            │   • AI coach service (LLM routing + PII scrub)    │
            └───────────────────────────────────────────────────┘
```

### 4.4 Accounts, privacy, regulatory

- **Accounts** become necessary the moment data leaves the device (cloud store + social). Until then Phase 1 can run local-first.
- **Health data is sensitive.** App-store review for HealthKit/Health Connect has specific requirements; cloud storage needs encryption at rest/in transit and a clear consent flow (the Fitbit→Google Health migration makes re-consent mandatory anyway).
- **SaMD line.** A coach that gives health/exercise advice can drift toward "medical device" framing. We keep "coach" language, add disclaimers, avoid diagnostic claims, and keep the TGA SaMD considerations (already familiar from MedScan) in view before the coach ships.
- **AI + PII.** Any cloud LLM call is preceded by PII scrubbing (the Presidio pattern already in use), and local models handle what they can.

---

## 5. Feature specifications by part

### Part 1 — Logs / data ingestion
- **Phase 1 (manual):** the existing bottom-sheet logger, generalised by `input` type (`weight_reps`, `score`, `duration`, `distance`). Writes canonical samples. Voice/conversational logging deferred to the coach phase.
- **Phase 3 (automated):** HealthKit adapter first (iOS), then the Google Health API (Fitbit), then Health Connect (Android). Each lands behind the canonical boundary, so adding one touches no UI.

### Part 2 — Graphs page
- Category card list (Strength / Performance / Recovery / Aesthetics / Context), each expandable to a full chart with adjustable time axis — close to the Google Health data screen the doc references.
- **Y-axis standardisation:** ranked metrics can plot in **rank space** (shared 0–8 axis) so unlike metrics are comparable; unranked metrics plot in their native unit.
- **Comparison & correlation:** multi-select overlay with a correlation readout. The prototype's Pearson-with-nearest-date-alignment logic is sound and carries over; we extend it with lag-aware correlation later (for the coach's "deep sleep drop → output drop" insight).

### Part 3 — Body graph & ranks  *(Phase 1 core — the make-or-break)*
- Front / Inner / Back SVG figures (the prototype's assets port over), coloured by tier; tap a region → detail sheet with progress bar, milestone ledger (now showing *derived* thresholds and honest percentiles), and inline logging.
- Overall + category rank cards (percentile-space scoring per §3.3).
- Glory tier rendering for the top tail.

### Part 4 — Habits  *(Phase 2)*
- **Reconcile two things.** The prototype already has a strong **planner/budgeter** (time, duration, cost, category, 24h density bar, monthly time/$ rollup) — keep it; it's a genuinely original angle. What's missing is the doc's **accountability layer**: per-day/week completion state, check-off, "quest"-style framing, and a daily achieved/missed summary.
- **Two-step verification** (doc's intent): a habit is "done" when a manual check-off **and** corroborating data agree (e.g. a logged lifting set *plus* a Health-app workout session in the same window). Implemented as a verification rule per habit type.
- **Calendar push:** habits surface on the user's calendar to reduce friction (calendar API integration, later in the phase).
- **AI-assisted goals:** default targets derive from ranks; the coach proposes adjustments (Phase 3 dependency).

### Part 5 — AI coach  *(Phase 3)*
- **Context tiers** map cleanly onto §2: ranked metrics + habits as primary context; tracked + background data as supporting context the coach can pull on demand.
- **Function set** (tool-calling over canonical data): sleep / diet / exercise / aesthetics review; strategic goal-setting; milestone discussion; correlation surfacing; **dynamic volume auto-regulation** (low readiness → temporarily restructure the habit checklist). These are real tools the model calls against the backend, not free-text guesses.
- **Agentic actions** (e.g. adjusting a habit's target) require explicit confirmation and are logged.
- **Guardrails:** coach-not-clinician framing, disclaimers, PII scrubbing before any cloud call, local model for routine queries.
- **Transparency:** a user-visible, sectioned view of exactly what context the coach holds, with deletable items — the doc's "structured categorised context" idea, which is also good privacy practice.

### Part 6 — Social / sharing / QoL  *(Phase 4)*
- Rank sharing (the badges are already shareable visual assets), friends, leaderboards within a cohort, native niceties. Built on the accounts system stood up in Phase 3.

### Part 7 — Underlying mathematics
- Fully specified in §3 and the appendix. The prototype's `rank.js` is the structural template; the math inside it is replaced.

---

## 6. Phased roadmap

We build **one phase at a time**, but the architecture above already accommodates all seven parts so nothing painful gets retrofitted. Each phase has an explicit exit gate.

### Phase 0 — Foundations
- Repo + Flutter scaffold; CI; the **pure Dart rank engine** with the corrected math (§3) and an exhaustive test suite.
- Canonical schema (§2) defined; metric registry authored; **standards v1 config** drafted with per-metric sourcing and `provisional` flags.
- **Exit gate:** engine passes golden-case + monotonicity + bodyweight-invariance tests; a handful of real lifts produce percentiles that *you* (Erol) judge as believable. This is the first reality check on immersion.

### Phase 1 — Graphs + Body graph (MVP)  ← *the make-or-break*
- iOS, manual logging only, local-first. Body graph with honest ranks, the graphs page, profile/badges.
- **Exit gate:** after real use, the ranks *feel right* — the exact judgement the prototype failed. If yes, the whole concept is validated cheaply. If no, we tune standards, not architecture.

### Phase 2 — Habits
- Completion/verification/quest layer on top of the existing planner; daily summary; calendar push.
- **Exit gate:** a week's habits can be set, auto/manually verified, and summarised.

### Phase 3 — Integrations + AI coach
- Accounts + cloud canonical store; HealthKit adapter; Google Health API (Fitbit) adapter; AI coach with the Phase-5 function set and guardrails.
- **Exit gate:** automated metrics flow end-to-end through the canonical boundary; coach answers and acts (with confirmation) using real context; PII scrubbing verified.

### Phase 4 — Social / QoL + Android
- Sharing, friends, leaderboards; Health Connect adapter for Android; polish.
- **Exit gate:** Android parity for core flows; sharing live.

**Division of labour (initial):** Erol — Flutter app, UI, product. Semih — backend, canonical store, adapters, data/integration. Claude — design, rank-engine + standards work, code review, and pairing across all of it.

---

## 7. Open decisions log

1. **Allometric exponent.** Default `BW^0.67`; revisit by fitting to whatever strength dataset we adopt.
2. **Barbell-lift cohort honesty.** Decide between labelling lifts as "vs trained lifters" or sourcing general-population proxies. (Highest-priority standards question.)
3. **Parametric vs empirical distributions** per metric — likely a mix; decide case by case as data is gathered.
4. **Accounts/auth provider** (Phase 3 trigger).
5. **Calendar API** target for Phase 2 push.
6. **Isolation-lift model** — confirm the rep-volume-at-load formulation per isolation metric.
7. **Female / age-banded standards** — explicitly v-next, captured so v1 schema leaves room (the standards config is already cohort-versioned, so this is additive).

---

## Appendix A — Corrected rank engine (pseudocode)

```
function percentile(metricId, rawInput, profile):
    m = registry[metricId]
    x = normalise(m, rawInput, profile)          # 1RM est, then /BW^0.67 if m.bodyweightScaled
    std = standards[m.standardsRef]
    P = cdf(std.distribution, x)                  # fraction of pop <= x
    if m.direction == -1: P = 1 - P
    return P                                       # "top (1 - P)"

function rankValue(metricId, rawInput, profile):
    P = percentile(metricId, rawInput, profile)
    topPct = (1 - P) * 100
    tier = tierIndexForTopPct(topPct)              # via fixed cutoffs 80/60/40/20/10/3/1/<0.1
    (loP, hiP) = tierPercentileBand(tier)
    frac = clamp01( (P - loP) / (hiP - loP) )      # fraction in PERCENTILE space
    if tier == TITAN and topPct < 0.1: return GLORY_extension(P)
    return tier + frac

function threshold(metricId, tier, profile):       # derived, never hand-typed
    std = standards[registry[metricId].standardsRef]
    P = 1 - tierTopPct(tier)/100
    xScaled = quantile(std.distribution, P)
    return denormalise(registry[metricId], xScaled, profile)   # back to real units

function overall(samplesByMetric, profile):
    ps = [percentile(id, latest(samplesByMetric[id]), profile)
          for id in rankedMetrics if has(samplesByMetric[id])]
    Pbar = inverseZ( mean( [z(P) for P in ps] ) )  # average in normal-quantile space
    return { rankValue: rankValueFromPercentile(Pbar), topPct: (1-Pbar)*100 }
```

## Appendix B — Metric tiers at a glance

- **Ranked (body graph):** chest/shoulders/biceps/triceps/forearms/lats/traps/abs/quads/hamstrings/glutes/calves (strength, bodyweight-scaled); 5k speed, plank, vertical jump, mobility (performance); VO₂max, HRV, resting HR, sleep score (recovery).
- **Tracked (graphs, unranked):** skin, oral, eye, grooming, hair density, voice.
- **Background (AI context):** heart-rate stream, skin-temp variation, cardio load, steps, active-zone minutes, sleep sub-metrics, total energy burned, food/macros, bodyweight* (*also the scaling input for strength).

---

*End of v0.1. Next: Phase 0 — stand up the Dart rank engine and the standards v1 config, then put real lifts through it and check the percentiles feel believable.*
