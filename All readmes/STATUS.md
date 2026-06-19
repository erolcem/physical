# Physical — Project Status & Handoff (v0.5)

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
- **Flutter app** (thin slice, runs on iOS):
  - Home: overall rank card, **front/back body graph** (muscles colored by tier,
    tap → detail), ranked-metric list.
  - **Metric detail sheet**: rank, progress, derived **tier ladder**
    (achieved/next/locked), log history (delete), inline log form.
  - **Persistence** via shared_preferences (write-through; survives restart).
  - **Progress view** (`ui/progress_screen.dart`, fl_chart): per-metric rank
    history over logged sessions, reached via the app-bar chart icon.
  - State: Riverpod. Storage seam: `Repository` interface.

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
- Tiers: Wood→Bronze→Silver→Gold→Platinum→Diamond→Champion→Titan (+ Glory,
  uncapped) at top 80/60/40/20/10/3/1/<0.1%.

## Provisional / open
- Strength **medians** modelled from grip-norms + prevalence; untrained centre is
  still an estimate (the one soft number). See `STANDARDS_METHODOLOGY.md`.
- Performance metrics (plank, vert, 5k) on provisional norms — next grounding pass.
- HRV is measurement-method dependent (flagged).

## Roadmap (build order)
0. ✅ Engine + corrected math + standards  
1. ✅ Graphs/body-graph MVP (manual logging) ← *we are here, polishing*  
2. Habits (completion/verification/quest + calendar)  
3. Integrations (HealthKit→canonical→cloud) + AI coach (PII-scrubbed, tool-calling)  
4. Social/QoL + Android (Health Connect)

## Candidate next steps
- Inner figure (organs → VO₂max/HRV/plank) to complete the 3-figure layout.
- Per-muscle metrics (light up the inert muscles).
- Ground performance-metric standards (plank/vert/5k).
- Port the SVG rank badges (`badge.js`) for a richer header.
- Backend bring-up (FastAPI + TimescaleDB canonical store).

## How to resume in a fresh chat
Paste this file + the current `lib/` files (or at least `rank_engine.dart`,
`metrics.dart`, `STANDARDS_METHODOLOGY.md`) and say what you want next. That's
enough to rehydrate fully.
