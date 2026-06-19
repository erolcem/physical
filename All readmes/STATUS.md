# Physical — Project Status & Handoff (v0.8)

**Purpose of this file:** if a chat gets long, start a fresh one and paste this
in alongside the current code files. It captures where the project is so work
resumes with no context loss. Updated as we go.

---

## What Physical is
A fitness app (Erol = primary dev, Semih = backend/integration, Claude = design +
code partner). It measures every trainable dimension of a healthy young male,
ranks each against the **general young-male population** (honest percentiles), and
shows that as tiered ranks on a body graph. Core principle: **a rank must be
honest or the gamification collapses.** Later phases add habits and an AI coach.

## Current state (what's built & working)
- **Rank engine** — validated, in two synced implementations:
  - `physical_rank_engine.py` (canonical reference; runnable, self-tested)
  - `rank_engine.dart` (faithful port; parity proven vs Python to ~1e-5 via
    `golden_vectors.json` + `rank_engine_test.dart`)
  - Features: allometric bodyweight scaling (/BW^0.67), distribution→percentile
    via CDF, **derived** tier thresholds (never typed), explicit lower-is-better
    `direction` flag, z-space overall, **bodyweight-at-time** (lifts scored
    against the weight when lifted), and **two-component mixture** strength
    standards (untrained mass + trained tail).
- **Flutter app** (runs on iOS; develop/preview on Linux/Chrome/Android — no Mac needed):
  - Home: overall rank card (**tap → category breakdown sheet**: Strength/
    Performance/Recovery sub-ranks with bars), **front/inner/back body graph**
    (all 22 ranked metrics mapped + lit; tap → detail), and **separate
    Strength / Performance / Recovery / Aesthetics** metric grids.
  - **Metric detail sheet**: rank, progress, derived **tier ladder**
    (achieved/next/locked), log history (delete), inline log form. Provisional
    metrics show a ⚠ estimate warning; tracked metrics show value (no medallion).
  - **Persistence** via shared_preferences (write-through; survives restart —
    covered by a round-trip test).
  - **Progress / graphs view** (`ui/progress_screen.dart`, fl_chart): a list of
    **category cards** (Strength/Performance/Recovery/Aesthetics/Sleep/Diet/
    Activity&Vitals/Body); each opens its **own graph page** (`CategoryGraphPage`)
    with that category's metrics as chips, **y-axis labels** (tier names in
    rank-space for ranked, native units for unranked, % for multi-compare),
    timeframe chips, a **Pearson correlation readout** for two-metric compares,
    and per-metric manual logging (diet/food/exercise included; auto-sync Phase 3).
  - **Rank badges** (`ui/badge.dart`): faithful metallic SVG medallions (the
    prototype's white-facet shading) with a radial halo + glow, bigger and
    decluttered (sub-rank shown as adjacent text, not on the gem).
  - **Mobile layout**: content constrained to a centered ≤500px phone column so
    it reads as intentional on any screen; overall-card sub-rank ticks now track
    the real bar width (was a screen-width approximation).
  - State: Riverpod. Storage seam: `Repository` interface.
  - **Tests:** 67 green — 48 engine-parity + 18 system-verification
    (`system_verification_test.dart`: registry↔engine integrity, PDF categories,
    every exercise ranks, weights/1RM, direction, category ranks, overall,
    persistence) + boot smoke.

## Architecture & stack (decided)
- **Client:** Flutter/Dart, iOS first. Rank engine = pure Dart package.
- **Backend (later):** Python + FastAPI on **PostgreSQL + TimescaleDB** (canonical
  store; imports the Python engine directly).
- **Data sources (later):** HealthKit (iOS, on-device) + Health Connect (Android)
  + Google Health API (Fitbit, cloud) — each behind an adapter normalizing to one
  **canonical schema** (the modularity comes from the canonical model + adapters,
  not just "one DB").
- **Three data tiers:** ranked (body graph) / tracked-unranked (aesthetics, graphs
  only) / background (AI context only).

## Flutter file layout
```
lib/
  main.dart                      (async; loads PersistentRepository, overrides provider)
  engine/rank_engine.dart
  data/metrics.dart              (registry: ranked/tracked/background + tier colors)
  data/body_figure_data.dart     (front/back SVG polygons, ported verbatim)
  data/repository.dart           (Repository interface + InMemory + demo seed)
  data/persistent_repository.dart(shared_preferences impl)
  state/providers.dart           (Riverpod)
  ui/home_screen.dart
  ui/body_graph.dart             (CustomPainter + tap hit-test)
  ui/metric_detail_sheet.dart
test/
  rank_engine_test.dart + golden_vectors.json
```
Deps: `flutter_riverpod`, `shared_preferences`, `fl_chart`. Engine math primitives (erf,
inverse-normal) are hand-rolled in Dart and parity-tested.

## Key decisions (locked)
- Reference population = **full healthy young male** (not just trained lifters) —
  for reachable, motivating, consistent ranks.
- Strength consolidated to **4 compound lifts** (bench/squat/deadlift/OHP) with
  defensible standards; body-graph muscles map to the lift that drives them;
  uncovered muscles (biceps/triceps/forearms/abs/calves) render inert for now.
- **Aesthetics are not ranked** (tracked scores only) — validity + wellbeing.
  *Now enforced in code:* skin/oral/eye/hair/grooming/voice are `MetricTier.tracked`
  with **no engine standard**, so they can't get a tier or feed the overall score.
- **Categories follow the PDF Table 1** (the source of truth): Performance =
  VO₂max/5k/vert/plank/deadhang/mobility/body-fat; Recovery = sleep-score/HRV/
  resting-HR; Strength = the 12 lifts. **Sleep score is ranked**, standardised from
  Fitbit/Google sleep-score data (`normal(77, 8)` — most users 72–83; provisional).
- Tiers: Wood→Bronze→Silver→Gold→Platinum→Diamond→Champion→Titan (+ Glory,
  uncapped) at top 80/60/40/20/10/3/1/<0.1%.

## Provisional / open
- Strength **medians** modelled from grip-norms + prevalence; untrained centre is
  still an estimate (the one soft number). See `STANDARDS_METHODOLOGY.md`.
- **Isolation lifts** (curl/lateral-raise/skull-crusher/forearm-curl/calf-raise/
  crunch) are ranked off a 1RM estimate the methodology doc flags as unreliable.
  They're now flagged **`provisional`** in the registry and show a ⚠ note in the
  detail sheet; the proper **rep-volume-at-load model is still a TODO**.
- Performance metrics **now grounded** (vert/plank/5k); 5k & plank are method-
  sensitive, mobility still unmodelled.
- HRV is measurement-method dependent (flagged).

## Roadmap (build order)
0. ✅ Engine + corrected math + standards  
1. ✅ Graphs/body-graph MVP (manual logging) ← *we are here; polish largely done, pending Erol's immersion check*  
2. Habits (completion/verification/quest + calendar)  
3. Integrations (HealthKit→canonical→cloud) + AI coach (PII-scrubbed, tool-calling)  
4. Social/QoL + Android (Health Connect)

## Candidate next steps
- ~~Inner figure / 3-figure layout~~ done. ~~Per-muscle metrics~~ done (all 22 lit).
  ~~Rank badges~~ done (faithful metallic SVG + halo). ~~Mobile sizing~~ /
  ~~graphs y-axis + correlation~~ done this session.
- **Erol's immersion/motivation check** on real logged data — the Phase-1 exit
  gate. Run on Linux/Chrome/Android (no Mac needed).
- **Isolation-lift rep-volume-at-load model** (replaces the flagged 1RM estimate).
- Ground remaining provisional standards (deadhang, mobility; pullup/hip-thrust/rdl
  anchors).
- **Backend bring-up (FastAPI + TimescaleDB canonical store)** — after the
  immersion check passes.

## iOS / deployment
See `IOS_DEPLOY.md`. For testing on a personal iPhone: **Xcode free provisioning,
free, no App Store** (7-day rebuild cycle). TestFlight / App Store need the $99/yr
Apple Developer Program. App is local-first, so it runs on device without a backend.

## How to resume in a fresh chat
Paste this file + the current `lib/` files (or at least `rank_engine.dart`,
`metrics.dart`, `STANDARDS_METHODOLOGY.md`) and say what you want next. That's
enough to rehydrate fully.
