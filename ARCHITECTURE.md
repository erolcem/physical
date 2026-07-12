# Physical — Architecture (comprehensive reference)

A complete, self-contained map of the system: the vision, every layer, the exact
math, the data model, the full API, end-to-end data flows, deployment, testing, a
line-by-line map of the PDF plan to the code, and a per-file index with notes on
what to change or improve.

Companion docs: `GUIDE.md` (day-to-day usage), `backend/DEPLOY.md` (hosting),
`backend/VERIFICATION.md` (Google review), `All readmes/` (the original design doc,
the plan PDF, `STANDARDS_METHODOLOGY.md`, `STATUS.md`).

**Status (verified):** the **entire plan (Parts 1–7, AI coach included)** is
implemented — including the two complex data types (exercise + diet) flowing into
both the ranks and the AI, and the coach's advanced behaviours (agentic actions,
dynamic volume auto-regulation, context transparency, strategic-correlation
pinning). **121 Flutter tests + 52 backend tests pass, 0 analyzer issues**, the
Python⇄Dart engine is parity-tested to ~1e-5, hosted on Railway, shipped to iPhone
via TestFlight. The coach runs on **Gemini** so the whole stack lives in the user's
Google account (sign-in, Health, Calendar, AI).

Code size: ~6,500 lines of Dart (app + engine), ~1,800 of Python (backend),
~1,300 of tests.

---

## 1. Vision & design principles

**Vision (one sentence):** measure every trainable dimension of the body, rank each
*honestly* against the general young-male population as tiered ranks on a body
graph, hold the user accountable with a habits + planner layer, log the hard stuff
(workouts, diet), and coach them with an AI that reasons over all of it.

**The principles that shaped every decision:**

1. **A rank must be honest or the gamification collapses.** Ranks are real
   population percentiles from defensible distributions, never typed-in numbers.
   This is why aesthetics are deliberately *not* ranked (no defensible distribution)
   and why isolation lifts use rep-volume instead of a fabricated 1RM.
2. **Local-first.** Ranks compute on-device from the user's own logs; the cloud is
   an opt-in mirror + integration hub, not a dependency. The app is fully usable
   offline.
3. **Single source of truth for the math.** The rank engine is written once
   (`physical_rank_engine.py`), ported to Dart, and the backend *imports the Python
   file directly* — so client and server ranks are identical, guarded by golden
   vectors.
4. **One canonical data model.** Every source (manual logs, Google Health, workout
   best-sets) normalises into one `sample` shape, so adding a source is an adapter,
   not a schema change.
5. **Three data tiers** drive the whole UI: **ranked** (body graph + ranks),
   **tracked** (graphed, never ranked — aesthetics), **background** (AI context
   only — steps, HR, sleep stages, …).
6. **Stay in one ecosystem.** Google for identity, health data, calendar, and the
   AI (Gemini) — minimal friction, one consent.
7. **Privacy by construction.** Per-user isolation everywhere; the coach is sent
   only PII-free metrics (never email/name/id); a transparency view shows exactly
   what it holds; agentic changes require explicit confirmation.

---

## 2. System overview

```
┌────────────────────────────────────────────────────────────────────────────┐
│  CLIENT — Flutter app (local-first; iOS device, Linux/Android/web for dev)   │
│  Tabs: Home · Progress · Habits · Coach                  (Riverpod state)    │
│  • Rank engine runs ON-DEVICE → instant ranks from local logs                │
│  • Opt-in cloud sync over HTTPS with a Bearer JWT                            │
│  • Logs: metrics, workouts (sets), food (macros+micros); habits; pins        │
└───────────────┬──────────────────────────────────────────────────────────────┘
                │ HTTPS (JWT)
┌───────────────▼──────────────────────────────────────────────────────────────┐
│  BACKEND — FastAPI, always-on on Railway                                      │
│  /auth · /me/samples · /me/ranks · /me/coach · /me/nutrition                  │
│  /integrations/google · /privacy /terms · /health                            │
│  • Imports the SAME rank engine → server ranks == client ranks               │
│  • Scheduled job refreshes Google data even with no device open              │
└───────┬───────────────────────────────┬───────────────────────┬───────────────┘
        │                               │                       │
┌───────▼─────────────┐   ┌─────────────▼──────────┐  ┌─────────▼──────────────┐
│ Postgres (canonical  │   │ Google Health API      │  │ Gemini (Generative     │
│ sample store + users │   │ (per-user OAuth):      │  │ Language API):         │
│ + Google tokens)     │   │ Fitbit → samples       │  │ coach + nutrition      │
└──────────────────────┘   └────────────────────────┘  └────────────────────────┘
```

**The eight layers** (detailed below): `A` rank engine · `B` Flutter app ·
`C` backend store+API · `D` auth/accounts · `E` Google Health integration ·
`F` habits · `F2` exercise+diet logging · `H` AI coach.

---

## 3. Layer A — the rank engine (the core)

The honest-ranking math, written once and kept in lockstep:
- `lib/engine/physical_rank_engine.py` — **canonical reference**, runnable + self-
  tested, and imported directly by the backend (`backend/app/engine.py`).
- `lib/engine/rank_engine.dart` — **faithful Dart port** for on-device ranking.
- Parity proven to ~1e-5 by `test/golden_vectors.json` (generated from the Python)
  + `test/rank_engine_test.dart`.

### 3.1 How a value becomes a rank
1. **Score** — bodyweight-scaled metrics (all strength lifts) divide the raw value
   by `BW^0.67` (allometric scaling, so a 60 kg and a 100 kg lifter compare fairly).
   Non-strength metrics use the raw value.
2. **Percentile** — the score runs through the metric's **distribution CDF**
   (normal / lognormal / two-component mixture). A `direction` flag (+1 / −1)
   handles lower-is-better metrics (resting HR, body fat).
3. **Tier** — the percentile maps onto a tier + sub-rank via **derived thresholds**
   (never hand-typed): tier entry points are population percentiles.

### 3.2 The tier ladder (exactly the PDF)
| Tier | Entry percentile (CDF) | "Top %" of population |
|---|---|---|
| Wood | 0.00 | top 99% (everyone) |
| Bronze | 0.20 | top 80% |
| Silver | 0.40 | top 60% |
| Gold | 0.60 | top 40% |
| Platinum | 0.80 | top 20% |
| Diamond | 0.90 | top 10% |
| Champion | 0.97 | top 3% |
| Titan | 0.99 | top 1% |
| **Glory** | 0.999 | top 0.1% (uncapped runway) |

Each tier splits into **sub-ranks I / II / III** (thirds of progress within it). The
continuous `rank_value` (0–8+) drives progress bars and the z-space overall.

### 3.3 Strength standards (the modelled part)
Strength can't be looked up, so it's a **two-component mixture** on the allometric
score: an untrained mass (grip-grounded spread) + a trained tail (prevalence-
weighted), each lift with untrained/trained ratios (× bodyweight). See
`STANDARDS_METHODOLOGY.md`. *This is the one provisional area — grounding these
medians with real data is the highest-value future improvement.*
- **Compounds** (bench, squat, ohp, pullup, hip_thrust, rdl) → ranked off an
  **estimated 1RM** (Epley/Brzycki/Lombardi average, capped at 12 reps).
- **Isolation lifts** (lateral_raise, curl, skull_crusher, forearm_curl) → ranked
  off **rep-volume-at-load** (`weight × reps`), because a 1RM is meaningless for
  high-rep work. Anchors = prior 1RM ratios × `_WORKING_SET` (≈ a 12-rep @ 70% set).
  The shared `strength_value`/`strengthValue` dispatcher picks 1RM vs rep-volume by
  metric id — used identically by the app and the backend.

### 3.4 Bodyweight-at-time
A lift is scored against the bodyweight the lifter was **when they lifted it**
(snapshotted on the log, immutable). Gaining weight never silently demotes past
ranks; getting leaner at the same load correctly raises *new* lifts.

### 3.5 Overall & category ranks
Computed in **z-space** (`engine.overall`) over the latest value of each ranked
metric — a statistically sound blend, not a naive average of tier numbers.
Categories: **strength**, **performance**, **recovery** (aesthetics tracked-only).

---

## 4. The data model

### 4.1 The three tiers (drive the whole UI)
- **ranked** — has an engine standard → gets a tier, appears on the body graph,
  feeds overall/category ranks.
- **tracked** — aesthetics; charted but **never** ranked (validity + wellbeing).
- **background** — AI-context only (steps, HR, sleep stages, energy, …).

### 4.2 The canonical `sample`
The one shape every source normalises into (`backend/app/models.py`):
`(user_id, metric_id, ts, value, bodyweight_at_ts, raw, source, source_id)` with
idempotent dedup on `(user, metric, source, source_id)`. `value` is the number the
engine reads; `raw` keeps the original `{weight,reps}`. The app's local `Log` is the
same idea on-device.

### 4.3 The metric registry (`lib/data/metrics.dart`) — the single source
Everything (grids, body graph, graph categories) is generated from this list:
- **Strength · ranked (12):** Chest/bench, Front-shoulder/ohp, Medial-shoulder/
  lateral_raise\*, Bicep/curl\*, Tricep/skull_crusher\*, Forearm/forearm_curl\*,
  Lats/pullup, Glute/hip_thrust, Quads/squat, Hamstrings/rdl, Calves/calf_raise\*,
  Abs/crunch\*  (\*= provisional flag shown in UI).
- **Performance · ranked (7):** vo2max, plank, vert, run5k_kmh, deadhang,
  hamstring_mobility, body_fat_pct.
- **Recovery · ranked (3):** resting_hr, hrv, sleep_score.
- **Aesthetics · tracked (6):** skin, oral, eye, hair, grooming, voice.
- **Background:** heart_rate, skin_temp, cardio_load, daily_readiness, exercises,
  steps, active_zone; the sleep sub-metrics; energy_burned, food_logs; lifting_sets;
  bodyweight (general).

The backend mirrors the **ranked** set in `backend/app/registry.py`; a test asserts
they never drift.

---

## 5. Layer B — the Flutter app

- **State:** Riverpod. **Storage seam:** the `Repository` interface — `InMemory`
  (tests/default + demo seed) and `PersistentRepository` (shared_preferences, one
  key per type: logs/habits/completions/food/workouts/pins). The whole app
  reads/writes through this seam; nothing touches storage directly.
- **Local-first:** ranks recompute reactively from `logsProvider`; cloud sync is the
  opt-in `cloud_sheet`.

**The four tabs:**
- **Home** (`home_screen.dart`) — the overall rank card (tap → breakdown sheet with
  **category bars**, **stats** (figure 4), and the **rank-distribution badges**
  (figure 3)); **coach-pinned correlation insights**; the front/inner/back **body
  graph** (tap a muscle → detail); per-category metric grids; aesthetics strip.
- **Progress** (`progress_screen.dart`) — Google-Health-style **category cards** →
  each opens its own **graph page** (timeframe chips; y-axis in rank/native/% space)
  + a **multi-metric comparison with a Pearson correlation** readout. Diet, Sleep,
  and Training cards open bespoke per-domain layouts.
- **Habits** (`habits_screen.dart`) — Layer F.
- **Coach** (`coach_screen.dart`) — Layer H.

(There is no Profile tab: all identity stats are auto-sourced — age from the Google
profile, height/weight/body-fat from synced logs — and surfaced via the coach, not a
manual form. Friends/social was removed.)

**Logging entry points** — the **Log** FAB offers *Metric* (a lift/field-test/vital),
*Workout* (`workout_screen`), *Food* (`diet_screen`).

---

## 6. Layer C — the backend (FastAPI canonical store + rank API)

`backend/app/` — FastAPI + SQLAlchemy 2.0, runs on **SQLite** (dev/tests) and
**Postgres** (prod); schema is DB-agnostic and auto-creates on startup. Imports the
canonical engine via `app/engine.py` (no copy, no drift).

### 6.1 Full API reference
| Method · path | Purpose |
|---|---|
| `GET /health` | liveness + engine metric count + tier list |
| `GET /privacy`, `GET /terms` | hosted legal pages (Google "Limited Use" disclosure) |
| `POST /auth/google/url` · `POST /auth/google/complete` | Google sign-in (browser code-paste): identity + health in one |
| `POST /auth/google` | native id_token sign-in |
| `POST /auth/dev` | dev-only passwordless sign-in (disabled in prod) |
| `GET /auth/me` | the signed-in account's email |
| `POST /me/samples` · `GET /me/samples` | bulk idempotent ingest (server-side `strength_value`) · list |
| `GET /me/ranks` | overall + per-category + per-metric ranks |
| `GET /me/nutrition/status` · `POST /me/nutrition` | Gemini nutrition auto-fill availability · infer macros+micros |
| `GET /me/coach/status` · `POST /me/coach/chat` · `POST /me/coach/context` | coach availability · chat (+ actions) · transparency context |
| `…/integrations/google/authorize|exchange|status|sync|debug|profile` | per-user Google Health linking + sync + raw debug + profile age |

All `/me/*` and `/integrations/*` routes are gated by `current_user` (JWT).

### 6.2 Ranking & sync
- `ranking.compute_ranks(samples)` → `(overall, categories, metrics)` — latest
  sample per ranked metric, scored at its bodyweight-at-time; reused by `/me/ranks`
  and the coach context.
- `jobs.py` (`python -m app.jobs`) — a scheduled job that refreshes every connected
  user's Google data so it's fresh before any device opens.

---

## 7. Layer D — auth, accounts & privacy

`auth.py` + `routers/auth.py` + `integrations/google_health/oauth.py`:
- **One Google authorization** carries `openid/email/profile` **and** the Google
  Health scopes — a single consent both creates the account (keyed by the Google
  `sub`) and links the data source.
- The backend issues an **HS256 JWT**; the app persists it (remembered across
  launches). `current_user` resolves it on every protected route.
- **Per-user isolation**: tokens and samples are all keyed by user id; no user can
  read another's data.

---

## 8. Layer E & integrations

### 8.1 Google Health (`integrations/google_health/`)
- `oauth.py` — consent URL (offline + the four health scopes) + token exchange/
  refresh.
- `client.py` — v4 dataType query (`DATA_TYPES`: resting-HR, HRV, VO₂max, weight,
  body-fat, sleep, + background steps/active-zone/energy).
- `mapping.py` — tolerant dataPoint→sample extractors (shapes vary; nested dates,
  string values); **derives `sleep_score`** (vendor score if present, else a
  transparent composite of duration/efficiency/deep+REM); expands sleep into
  duration / efficiency / deep / REM.
- `router.py` — authorize/exchange/status/**sync**/**debug** + the reusable
  `sync_user()` the scheduled job calls.

### 8.2 Gemini (`integrations/gemini/client.py`)
A thin client over the Generative Language `generateContent` REST shape (system
instruction + turns → reply), keyed by `GEMINI_API_KEY` from Google AI Studio.
Never raises into the app — errors become a clean message.

---

## 9. Layer H — the AI coach (deep)

`backend/app/coach.py` + `routers/coach.py` + `integrations/gemini/client.py` +
`ui/coach_screen.dart`.

- **Context** (`build_context` / `context_sections`) — a compact, **PII-free** block
  from the user's *real* data: overall + category ranks, weakest vs strongest
  metric, recent recovery readings (from the canonical store), plus the app-supplied
  **habits, profile, today's diet, last-7-day training (volume/sessions/muscles),
  and tracked aesthetics**. No email/name/id ever leaves.
- **System prompt** — coach-not-clinician framing, "ground every claim in the data,
  never invent numbers," prioritise the weakest areas.
- **Agentic actions (with confirmation)** — the model emits fenced ` ```action `
  JSON blocks; `parse_actions()` safely extracts + sanitises them (bad/unknown
  dropped, never raises). The app renders each as an **Apply** card:
  - `add_habit` / `remove_habit` → runs through the habits notifier;
  - `pin_correlation` → pins a metric pair to the dashboard.
  Nothing changes without the user's tap; then it shows "Applied ✓".
- **Dynamic volume auto-regulation** — poor recovery markers → the coach proactively
  proposes easing the plan (lighten a heavy habit / add mobility).
- **Strategic correlations** — the coach can pin a likely metric relationship; the
  dashboard's *Coach insights* computes the real **Pearson r** from local logs.
- **Transparency** — the "What I see" sheet (`/me/coach/context`) shows the exact
  sectioned context, so the user sees precisely what is and isn't shared.

---

## 10. Layers F & F2 — habits, exercise, diet

### 10.1 Habits (`data/habits.dart`) — scaffolded
A habit is **scaffolded**, not free-text: it lives in a **section**
(sleep / exercise / diet / aesthetics / recovery / misc) and is a **preset** from
that section's in-realm menu (`habitPresets`) or a **bounded custom** title — so
data checks stay valid and the AI can reason. Each habit has a **verify mode**:
`metric` (a same-day log of a linked metric), `workout` (a session that day),
`diet` (a food log that day), or `manual`; `statusFor` → verified / manual / not-
done. **Cadence** is daily or **weekly with chosen days** (`isDueOn`), with an
**ideal time + duration** that drive the **Google Calendar recurrence** (daily or
weekly `BYDAY`) and the **reminder**. The Habits tab shows today's actionable
roster, a **weekly schedule** bar, per-habit **streaks** + a 7-day dot strip, and
dims habits not scheduled today. (Monthly-cost was dropped per review.)

### 10.2 Workout logging (`data/workout.dart`, `ui/workout_screen.dart`)
A real **tracker**: add an exercise → log its sets (weight × reps), repeat
(`groupByExercise` renders sets grouped under each exercise). A session yields
**total volume** (Σ weight×reps) + the **best set per exercise**, which updates that
lift's rank (1RM/rep-volume). 7-day rollups (volume/sessions/muscles) feed the coach.
*Remaining:* time-window dual-authorisation against the Google Health exercise
session (needs the auto-exercises sync).

### 10.3 Diet logging (`data/diet.dart`, `ui/diet_screen.dart`, `app/nutrition.py`)
A **holistic diet page**: food entries with macros (kcal + P/C/F + **fibre**) **and a
micronutrient map** → **daily totals** with a **macro-kcal breakdown bar**, **summed
micros**, and a **7-day calorie trend** (`caloriesLastNDays`), fed to the coach. The
Progress "Diet" subpage routes here (its own domain layout); **Sleep**
(`ui/sleep_screen.dart`) and **Training** (the workout screen's analytics header)
likewise have bespoke per-domain layouts.

**Nutrition auto-fill (Gemini-inferred micros).** Rather than a brittle food DB,
"Auto-fill nutrition with AI" sends the typed food to `POST /me/nutrition`, which asks
Gemini for a fixed set of macros + 8 micronutrients in fixed units (`nutrition.py`'s
defensive parser coerces/clamps and rejects junk). Keys are unit-suffixed
(`sodium_mg`, `vitamin_d_ug`, …) so they sum cleanly. Falls back to manual entry when
the AI key is unset (503).

---

## 11. End-to-end data flows

- **Manual log → rank (offline, instant):** detail sheet → `Repository.saveLog` →
  Riverpod recomputes on-device via the Dart engine → body graph + cards + overall
  update.
- **Workout → ranks + AI:** workout screen builds sets → `WorkoutNotifier.add`
  stores the session **and** adds a rank log for each best set; the 7-day training
  rollup is sent to the coach on the next message.
- **Opt-in cloud sync:** Cloud sheet → `performSync` pushes samples to `/me/samples`;
  `cloudSync` triggers a Google pull then merges new samples into the local store.
- **Google Health (server-side):** `/integrations/google/sync` (or the scheduled
  job) → refresh token → `client.query` per dataType → `mapping.to_samples` (+
  derived sleep score) → dedup-ingest into Postgres → `/me/ranks` + next app sync.
- **Coach chat:** Coach tab gathers ranks (backend) + habits/profile/diet/training/
  aesthetics (app) → `/me/coach/chat` builds the PII-free context + prompt → Gemini
  → reply + parsed actions → chat bubble + Apply cards.

---

## 12. Deployment & ops
- **Backend:** `backend/Dockerfile` (built from repo root so the shared engine is
  bundled) → **Railway** (`railway.json` pins the Dockerfile) + managed Postgres +
  a cron service for `python -m app.jobs`. Env: `DATABASE_URL`, `JWT_SECRET`,
  `GOOGLE_CLIENT_ID/SECRET`, `GOOGLE_REDIRECT_URI`, `ALLOW_DEV_AUTH=false`,
  `CONTACT_EMAIL`, `GEMINI_API_KEY`, `GEMINI_MODEL`. See `backend/DEPLOY.md`.
- **iPhone:** **Codemagic** cloud-Mac build → **TestFlight** (`codemagic.yaml` bakes
  in `BACKEND_URL`). See `GUIDE.md`.
- **App backend URL:** defaults to the hosted Railway URL; override with
  `--dart-define=BACKEND_URL=…` for local backend dev.

---

## 13. Testing (167 total)
- **Flutter (121):** engine parity vs golden vectors; system-verification
  (registry↔engine, PDF categories, every lift ranks, directions, overall/category);
  habits (streaks/verification/planner/weekly/calendar); diet (macros/micros)/workout;
  correlation; notifications; sync; and an **all-tabs runtime smoke test**.
- **Backend (52):** engine load + coverage; auth; samples (isolation rep-volume +
  raw 1RM); ranks; Google Health mapping (every dataType shape + derived sleep score
  + sub-metrics); nutrition inference (parser + endpoint); coach (PII-free
  context incl. diet/training/aesthetics, agentic + pin parsing, Gemini mocked,
  guards); legal pages.

---

## 14. PDF plan → implementation map (every detail)
| PDF | Status |
|---|---|
| **Part 1 — Logs** (12 strength, performance, recovery, aesthetics, background) | ✅ all metrics; strength yields volume (workout) + 1RM/rep-volume (rank); stats auto-sourced (no profile form) |
| Part 1 — diet macros **+ micronutrients** | ✅ Gemini-inferred at log time (`/me/nutrition`) |
| Part 1 — background auto-Google (steps/zone/energy) | ❌ no daily-rollup type in the API (confirmed via live `/debug`) |
| Part 1 — auto height/age + deeper sleep sub-metrics | ✅ age (Google profile) + sleep time-to-sleep/awakenings/local-day wired; height via a `height` dataType (confirming shape) |
| Part 1 — 5k auto-from-running, auto "exercises", aesthetic vision/audio models | 🟡 need a Google exercise-session endpoint (absent) / 3rd-party models (manual fallbacks built) |
| **Part 2 — Graphs** (category cards → custom graph; comparison + correlation) | ✅ |
| **Part 3 — Body graph & Ranks** (clickable body graph; card w/ progress+log+milestones; 8 tiers + I/II/III + Glory; category+overall; **rank-badge distribution fig 3**; **overall stats fig 4**; **correlation engine fig 5**) | ✅ all |
| **Part 4 — Habits** (check-off, verification, planner, density bar, weekly, calendar) | ✅ |
| **Part 5 — AI coach** (sleep/diet/exercise/aesthetics review; goals; milestones; notifications; habit-aware; structured context; agentic actions; dynamic volume auto-regulation; strategic correlations) | ✅ (voice logging intentionally skipped) |
| **Part 6 — Friends / sharing / QoL** | ✖ removed by design (not wanted for distribution) |
| **Part 7 — Underlying mathematics** | ✅ exceeds the doc; parity-tested |

---

## 15. File map (every file: what it does · what to improve)

**Engine (keep in parity):**
- `lib/engine/physical_rank_engine.py` — canonical math. *Improve: ground untrained/
  trained medians + isolation anchors with real data.*
- `lib/engine/rank_engine.dart` — Dart port. *Edit only in lockstep; golden vectors
  guard drift.*

**App · data (`lib/data/`):**
- `metrics.dart` — THE metric registry. *Add/edit metrics here.*
- `repository.dart` — storage seam (interface + InMemory + demo seed). *One place to
  add a new stored type.*
- `persistent_repository.dart` — shared_preferences impl (per-type keys). *Add a v2
  migration if a model's JSON changes.*
- `sync.dart` — cloud sync + `kBackendUrl` + `apiClientProvider`.
- `api_client.dart` — every backend HTTP call. *Centralise error→message mapping.*
- `habits.dart` — Habit model + streaks + verification + planner + density + weekly
  + calendar URL + per-day metric series (`valuesLastNDays`).
- `diet.dart` — FoodEntry (macros + micros map) + daily totals (summed micros).
  Micros are Gemini-inferred via `app/nutrition.py` + `POST /me/nutrition`.
- `workout.dart` — WorkoutSession/Set → volume + best-set. *Add two-step verification
  vs a Google Health workout session.*
- `correlation.dart` — Pearson + day-alignment + pin model.
- `notifications.dart` — daily habit reminders (guarded iOS/Android). *Verify on
  device; add iOS foreground-present delegate.*
- `body_figure_data.dart` — front/back/inner SVG muscle polygons.

**App · state (`lib/state/`):** `providers.dart` (logs/ranks/overall/category),
`habit_providers.dart`, `log_providers.dart` (diet/workout/pins).

**App · UI (`lib/ui/`):**
- `main_screen.dart` — 4 tabs + Log FAB chooser + reminder re-sync.
- `home_screen.dart` (largest, ~800 lines) — overall card, breakdown sheet (figs
  3/4), pinned insights, body-graph section, metric grids. *Candidate to split.*
- `progress_screen.dart` (~590) — category cards → graph page + correlation.
  *Candidate to extract the chart widget.*
- `habits_screen.dart`, `coach_screen.dart`, `metric_detail_sheet.dart`,
  `diet_screen.dart`, `sleep_screen.dart`, `workout_screen.dart`,
  `body_graph.dart` (CustomPainter + hit-test), `badge.dart` (SVG medallions),
  `cloud_sheet.dart` (sign-in + sync + Google-data inspector).
- `main.dart` — entry; loads repo, fires notification setup, runs app.

**Backend (`backend/app/`):** `main.py`, `config.py`, `db.py`, `models.py`,
`schemas.py`, `engine.py`, `ranking.py`, `registry.py`, `jobs.py`, `auth.py`,
`coach.py`, `nutrition.py`; `routers/` (auth/health/legal/ranks/samples/coach/
nutrition); `integrations/google_health/` (oauth/client/mapping/router);
`integrations/gemini/client.py` (*add streaming + true function-calling*).

**Tests:** `test/` (Dart) + `backend/tests/` (Python).

**Config / docs:** `pubspec.yaml`, `analysis_options.yaml`, `codemagic.yaml`,
`railway.json`, `backend/Dockerfile`, `backend/DEPLOY.md`, `backend/VERIFICATION.md`,
`GUIDE.md`, `ARCHITECTURE.md`, `All readmes/` (design doc, the plan PDF, STATUS,
STANDARDS).

---

## 16. Known limitations & future work (prioritised)
1. **Ground the strength standards** with real data — the one provisional spot; most
   improves rank honesty.
2. **Google background types confirmed via live `/debug`:** sleep sub-metrics
   (time-to-sleep, awakenings, local-day) + age are wired; steps/active-zone/energy
   have **no daily-rollup type** and an exercise-**session** endpoint **doesn't exist**
   (404), so two-step workout verification stays blocked upstream.
3. **Coach upgrades** — streaming replies, true function-calling.
4. **Split the two big UI files** for maintainability.
6. **External setup** — set `GEMINI_API_KEY`; clear the Apple Paid-Apps agreement to
   unblock TestFlight + on-device verification of notifications; Google CASA
   verification (only for public release).
7. **Voice logging** — intentionally out of scope.

---

## 17. Owner review (round 2) — corrected vision & build roadmap

Captured verbatim-in-spirit from the owner's review so nothing is lost. Each item:
current state → target → priority. (Setup for any user is in `AI_SETUP.md`.)

**Guiding correction — auto over manual (seamlessness).** If a metric *can* be
auto-logged, it should be, not typed.

**✅ DONE · Profile removed; stats fully auto-sourced.** The manual Profile tab (and
Friends/share) were removed for distribution. Identity stats now flow without a form:
**age** from the Google profile (`/integrations/google/profile`), **weight + body-fat
+ height** from synced logs (`height` dataType added), **gender** defaults to the
young-male cohort. The coach reads all of these; nothing is typed.

**🟡 MOSTLY DONE · Workout logging = a real tracker.** Shipped: sets grouped under
each exercise (add exercise → log its sets), per-exercise + total load/volume,
best-set updates the rank; an exercise habit verifies off a same-day manual session.
*Blocked:* the full **time-window dual-auth against a Google exercise session** —
live `/debug` showed `/users/me/sessions` returns **404** (this API doesn't expose
exercise sessions at that path), so the Google half isn't available yet.

**✅ DONE · Per-domain graph layouts (Diet · Sleep · Training).** Each domain has its
own bespoke subpage, not the generic metric chart: **Diet** (kcal + P/C/F + **fibre**,
macro-kcal bar, 7-day calorie trend), **Sleep** (last-night deep/REM/light stage
breakdown, 7-night score + hours-asleep trends, efficiency/time-to-sleep/awakenings
stats), **Training** (7-day volume trend + week totals on the workout screen).
**Micronutrients** are now inferred by Gemini at log time (no food DB) — see §10.3.

**✅ DONE · Habits = structured & data-aligned, not free-text.** Shipped: sections +
in-realm presets + bounded custom; verify modes (metric/workout/diet/manual)
auto-corroborated by the day's logs; ideal time + duration; daily/weekly-by-day
cadence; today's roster + weekly schedule; monthly-cost dropped. *Next refinements:*
per-habit explicit numeric targets (e.g. "protein ≥ 150 g") checked against the day's
totals, and goal-emphasis the coach remembers.

**✅ DONE · Graphs & ranks — accessibility + "epic" polish.** Fixed the **"All"
timeframe** label crowding; added a **specular light-catch sheen** to every medallion
(lustier by tier) and an **animated shine sweep** on the big hero badges. *Further
(optional):* commission custom raster badge art if the SVG medallions ever feel
limiting.

**✅ DONE · AI coach — fixed context + fixed response selection.** Shipped: a fixed
menu of coach functions (Sleep/Diet/Training/Aesthetics review, Set a goal, My
progress, What should I improve?) in the welcome + a mid-chat Functions sheet, each
sending a structured prompt. Context stays structured per Table 3 (Sleep / Diet / Exercise / Aesthetics
review; Strategic goal-setting with an emphasised goal + plateau detection; Milestone
discussion; Notifications; Habit-update-aware; deletable structured context;
autonomous strategic-correlation pinning; dynamic volume auto-regulation on a
daily-readiness drop). Voice = out of scope.

**Build order:** (1) ✅ **Habits redesign** → (2) 🟡 **Workout tracker** (grouped sets +
per-domain analytics done; Google-session dual-auth unavailable via the API) →
(3) ✅ **Per-domain layouts** (Diet + Sleep + Training) **+ Gemini-inferred micros** →
(4) ✅ **Profile removed; stats auto-sourced** (age/height/weight/body-fat auto;
gender defaults to cohort) → (5) ✅ **Rank-badge/graph polish** (sheen + hero shine) →
(6) ✅ **Coach fixed-response selection**. Each shipped behind its own tests. **The
roadmap is complete.** The one remaining external-data item — workout↔Google
exercise-session dual-auth — is blocked by Google not exposing a sessions endpoint.

**Next unblock:** an in-app **Cloud → Inspect Google data** button now copies the raw
Google field shapes — paste that to wire the live-data items (workout dual-auth,
height/DOB, deeper sleep, step/energy names).

---

## 18. Owner review rounds 3–5 (July 2026) — the AI-verification era

Major architectural additions since §17, in the order they shipped:

**Habits are AI-verified, strictly.** A data-verifiable habit (metric/diet/workout)
counts ONLY from real evidence; manual ticks work only for inherently manual habits.
`POST /me/habits/verify` (`habit_check.py`) sends the day's full evidence — sessions
with sets, food log, every metric reading — to Gemini with an **evidence-exclusivity**
rule (one workout can't tick two habits) and binding numeric targets. Verdicts are
stored per habit+day (`aiVerdicts` in the repo) and OVERRIDE the rule-based check
(`habitDoneOn`); verification re-runs on every sync and (debounced) whenever local
evidence changes, plus an on-demand "AI check" button.

**Sets are watch-anchored (the PDF's two-step verification).** Google exercise
sessions import on every sync; manual set-logging sessions auto-link to the tracked
watch exercise covering the same window (`linkSessionsToWatch`, ±45 min slack).
Sessions render "✓ watch" / "⚠ unverified", and the verifier is instructed never to
credit exercise habits from unverified typed sets.

**The habit carries the plan.** `Habit.templateId` links an exercise habit to its
`WorkoutTemplate` (exercises + sets). Due habits offer one-tap "start" (pre-filled
session; edit to what actually happened); the Exercise page opens with a Today's-Plan
card; a template editor + Hevy-style template chips cover manual management.

**"Plan my week" (AI roster builder).** `POST /me/coach/plan` (`planner.py`): the
Pro-tier coach reads the full context + an optional emphasised goal and proposes a
complete scaffolded roster — habits with targets/times/days AND the workout plans —
sanitised defensively and applied via a review sheet (optionally replacing the
current roster).

**Coach context, maximal.** 365-day downsampled history (90 pts/metric, up to 80
metrics), 14 sessions of individual sets, real day-aligned correlations, energy
balance, and the actual MEALS of the last week. Two model tiers: `GEMINI_MODEL`
(pro; chat/digest/planner) + `GEMINI_FAST_MODEL` (flash; nudges/nutrition/verify).

**Google integration, split-token.** health.googleapis.com rejects tokens carrying
non-health scopes (`DISALLOWED_OAUTH_SCOPES: cl_events`), so Calendar lives on its
own consent + `google_calendar_tokens` row. Calendar pushes use **deterministic
event ids** (sha1 of the habit id) making duplicates structurally impossible, with a
reconcile pass that heals strays and prunes removed habits; weekly events anchor on
the next matching weekday; pushes are auto-triggered on habit changes and serialized
app-side. Status/debug endpoints diagnose missing scopes, poisoned tokens, and
disabled APIs by name.

**Deletes stick.** Entity tombstones (`habit:`/`food:`/`workout:`/`template:` keys)
ride the backup snapshot, so deletions survive merges and propagate across devices;
"Reset cloud data" wipes both the sample store and the backup blob (`DELETE
/me/samples`, `DELETE /me/backup`). Google-synced daily values (steps etc.) upsert on
revision instead of freezing at first sight; rank/readiness history is live
(backfills replace stale days) and fully resettable.

Tests: **302 Flutter + 121 backend** (round 5).

## 19. Owner review round 6 (July 2026) — children, pins, and honest graphs

**Sets are children, structurally.** A set cannot exist as its own workout: the
Exercise FAB is "Log sets", which drops the user into today's tracked watch
exercise (chooser when several). With no tracked exercise yet, sets are *pre-logged*
into a holder shown under "WAITING FOR THE WATCH EXERCISE" (never as a sibling
workout) that auto-absorbs into the covering watch session — now on *every*
mutation, not just import, so a holder created while a watch session already
exists merges instantly. Parents record `absorbedIds`, so an open detail screen
re-binds seamlessly when its holder merges away, and `WorkoutNotifier.resolve()`
follows the trail for late set-adds. Manual duration typing is gone (fabricated
minutes were the loophole).

**AI pins (`AiPin`).** Free-text standing goals/context ("cutting to 78 kg by
September") live in the Habits tab's 📌 section next to the coach's pinned
correlation insights (moved off the front page). They ride every coach request
(chat/plan/nudge/digest) as a "Pinned by user" context block, appear in the
transparency sheet, sync via the backup with `aipin:` tombstones, and the coach
itself can propose one (`pin_note` action, one-tap confirm).

**Honest data fixes.** "Time to Sound Sleep" derives from the stage timeline
(bedtime → first DEEP block) because Fitbit reports `minutesToFallAsleep` as a
flat 0 — a 0 is never logged blind. Age derives from a stored date of birth (tap
AGE on the body strip) and re-logs itself when a birthday passes; DOB rides the
backup (fill-gap merge, never clobbered). The diet energy graph grew labeled
axes, tooltips, a banded kcal scale, and an *avg in / avg out / net* headline
with the expected kg/week vs what the scale actually says; the weight strip
shares its x-range. Habit streaks count **due days** (`dueStreak`) so weekly
habits build real streaks; long-press opens a weekday-anchored 8-week heatmap
with adherence %, edit and delete. New verify rule `rank_log` powers "Rank
check-in" habits (counts the day's manually-tested ranked-metric logs; AI
verification skips it — the rule is already exact). Rank engine sanity is now a
property test: every standard's tier ladder must be ordered, monotone, bounded,
with plausible human anchors pinned.

Tests: **319 Flutter + 130 backend.**

## 20. Owner review round 7 (July 2026) — precise verification & UX polish

**Verification is now precise, and on the pro model.** Habit verification moved
from the fast model to `gemini-2.5-pro` — it's correctness-critical (a false tick
corrupts the whole accountability system) and low-frequency (a sync + a debounced
re-check per day), so pro-class reasoning is the right cost trade; nudges and
nutrition stay on flash. Every habit now carries a free-text **`description`** (all
categories) — the user's own definition of what counts — sent to the verifier and
the coach. The verify prompt gained: *be specific, not generic* (a "Makiwara
punching (evening)" habit is NOT satisfied by a Walk), *honour the description as
binding*, and *respect time-of-day* — and the evidence payload now includes each
session's `start_time` so the model can enforce it. The planner emits a
`description` for the habits it proposes.

**Sets/templates live inside the imported exercise.** The session detail screen
(including a Google-imported one) gained "Add sets from a plan"
(`applyTemplateToSession` appends a template's sets as children of the exercise —
never a new entity), and delete is hidden for Google sessions (real data you add
to, not remove).

**Configurable daily briefings.** The morning brief / evening digest times are
user-set (Cloud sheet → *Daily AI briefings*, default 08:00 / 20:00) instead of
hard-coded 8/20; they're a local device preference (`saveNudgeHours`, not in the
backup) and re-scheduled from live data on each sync. The coach Functions sheet is
scroll-controlled so every option is reachable on small phones, and the AGE cell
lost its 🎂.

Tests: **322 Flutter + 131 backend.**

## 21. Full review + rank audit (July 2026)

**Habits/AI review — fixes shipped.** (1) `isDueOn` ignored `createdAt`, so a new
habit's 8-week heatmap and adherence (and the adherence reported to the coach)
counted due days from before it existed as "missed". Added `isDueAndActive`
(due AND on/after creation), wired into the heatmap, both adherence paths, and
`dueStreak` (stops at the creation day). (2) AI verdicts (per habit×day) rode the
cloud backup unbounded, pushed every sync — export now trims to the last 180 days
(older days recompute via the rule-based check; local storage untouched).

**Rank engine audit — no changes, confirmed sound.** Property + edge-case sweep:
every standard's tier ladder is ordered, percentiles monotone and bounded, every
extreme clamps to rank_value ∈ [0,9] and top_pct ∈ [0,100], bodyweight-scaled
lifts guard a missing bodyweight, and empty/unknown inputs degrade to Wood. All
directions are correct (resting_hr / body_fat / blood_pressure / eye / voice /
sprint are lower-is-better). Headline calibration holds on realistic profiles:
untrained→Bronze, 2–3yr lifter→Gold, competitive amateur→Champion. Owner
decisions (kept): health targets (≤12% body fat, ≤105 systolic) award Glory as
the attainable path to the top tier; the flagged provisional curves stay until
validated population data is available to ground them.

Tests: **327 Flutter + 131 backend.**

## 22. Verification-scope correctness (July 2026)

The LLM verdict used to override the rule for EVERY non-manual habit — including
deterministic ones. But a metric/diet/rank_log habit has an exact measured value
(a protein total, a diet-health score the LLM can't even recompute, a sleep
reading vs its target), so letting the model re-guess it could only introduce
arithmetic error over a correct computation. The LLM now judges **workout habits
only** — the sole case where the rule is genuinely ambiguous (which session
counts for which habit, evidence-exclusivity, custom-activity/time matching like
"evening makiwara"). `habitDoneOn` honours an AI verdict only for `verify ==
'workout'` (which also neutralises any legacy verdict left on a since-retyped
habit); everything else verifies from its exact rule. `verifiableHabitsOn` sends
only workout habits, cutting needless AI latency/cost too. Also: weekly habits
now schedule reminders on their due weekdays (not daily); the app re-syncs on
resume when the day changes (fresher briefings without server push); a new
habit's heatmap/adherence/streak no longer count days before it existed; and the
AI-verdict backup is bounded to 180 days.

Tests: **332 Flutter + 131 backend.**

## 23. Accessory lifts, Hevy-style sets, structure-only templates (July 2026)

**Accessory lifts now rank on estimated 1RM, not rep-volume.** Weight×reps rewarded
grinding reps at a light load (10kg×12 beat 12.5kg×8); every lift — isolation
included — now uses the capped Epley est-1RM (reps clamped at 12 where the formula
holds), so ranking reflects STRENGTH. Isolation standards rebased from
`ratio×working-set` to plain 1RM ratios × bodyweight (Python + Dart + golden
vectors, with fresh isolation golden cases). `isolationLifts` is kept only to flag
"estimated from a working set" in the UI.

**Sets are Hevy-style and templates are structure-only.** Tapping an existing set
in the exercise detail edits it in place (`updateSet`), including a Google-imported
session — nothing lives in a separate area. A `WorkoutTemplate` now stores STRUCTURE
only: exercises + how many sets of each, no weights/reps (you can't predict a future
workout's loads). The plan editor adds exercises by name + set count + mode;
`fromSession`, the AI planner, and every apply path strip values via `blankSets`, so
applying a template drops EMPTY slots (`WorkoutSet.isBlank`) into the exercise that
read "Tap to log" until you fill in what you actually lifted.

**Smaller wins.** The Progress page's Exercise header gained its own 7-day
training-volume sparkbar (matching Sleep/Readiness/Health headers); the duplicate
"LAST 7 NIGHTS · HOURS ASLEEP" bar was removed from the Sleep screen (it's already
in the graph area below); and the Diet screen gained AI food entry — describe a
meal, Gemini fills kcal/macros/health, confirm, save.

Tests: **345 Flutter + 131 backend.**

## 24. Owner review round 8 (July 2026) — release-readiness pass

**Sets reliably land inside the watch exercise.** Three real defects fixed:
(1) *Linking was window-only.* A holder's timestamp is when you TYPED the sets —
routinely hours after training — so the ±45-min overlap never matched and holders
sat in "WAITING FOR THE WATCH EXERCISE" forever. `linkSessionsToWatch` now
prefers a window overlap but falls back to the NEAREST same-day tracked
exercise (never cross-day). (2) *Index-based set edits could corrupt a
neighbour.* If the holder absorbed into its watch parent while an edit dialog
was open, the captured index pointed at a different set. The UI now edits by
SET REFERENCE (`updateSetRef`/`removeSetRef`: instance identity → equal-values
fallback → no-op), resolved at apply time. (3) *Sets didn't propagate across
devices.* `repoMerge` skipped any workout id it already had, so sets typed on
the other device stayed there forever; the merge now adopts the RICHER set
record for the same id (more sets wins — a strict superset never discards),
carries a missing title/link, unions the absorption trail, and `cloudSync`
re-runs the relink/absorb pass after the merge.

**AI food entry is multimodal — text + photo, never photo alone.** The Add-food
dialog attaches an optional meal photo (camera/library, downscaled to ≤1280px);
`POST /me/nutrition` forwards it to Gemini as an inline image with explicit
guidance: the DESCRIPTION is authoritative for what the food is, the PHOTO
refines portion size/preparation/sides. An empty description is rejected even
with a photo (422) — visual-only food ID is too error-prone to trust — and
oversized images 413.

**Weight & body-fat are first-class manual entries.** The home body strip's
HEIGHT and WEIGHT cells are now tappable (quick numeric log, same as AGE→DOB);
the Diet energy card's Weight stat logs the day's scale reading; body-fat was
already loggable from its Recovery card. Google Health sync still fills all of
these automatically — manual is the always-available path, not a fallback mode.

**Profile = numeric entries, not graphs.** The Progress tab's Profile category
no longer opens a graph page: a dedicated Profile screen shows Age (DOB-derived),
Sex (reference population), Height, Weight and Body fat as plain numbers with
one-tap entry. (Weight still charts on the Diet page where it belongs.)

**The energy balance is honest and readable.** "Out (est)" was raw Mifflin BMR +
workout kcal, under-reading a real day by ~20% and showing a phantom surplus on
every unsynced day. The estimate is now `BMR × 1.2 (sedentary baseline) +
tracked workout kcal` (`estimatedDailyBurn`), used by both the today card and
the trend; the card reads "IN − OUT = NET" with the formula spelled out, and the
trend states its averages count only logged days (gaps are gaps, not 0-kcal
fasts). Synced watch totals still override the estimate.

**Rank audit (all 27 standards swept, 2 recalibrated, 1 UX trap closed).**
Full-profile calibration verified: sedentary → Bronze I (top ~78%), average
active → Gold I (~37%), dedicated 2–3-yr lifter → Platinum III (~13%),
exceptional → Champion III (~1.6%); every median landmark lands Silver II / top
50% by construction. Fixes: **hamstring_mobility** N(15,5)→N(2,9) with the scale
defined as *cm past the toes* (the old curve ranked a toe-toucher bottom 0.1%);
**pushups** N(35,13)→N(25,12) (median young man ~25/min, not 35); the **pullup**
forms now say *Total weight = bodyweight + added load* (the standard reads total
system weight — typing only the added plate ranked a real pullup Wood). Golden
vectors regenerate via the committed `backend/scripts/gen_golden.py` (inputs
preserved, expecteds recomputed); backend anchor tests pin the new curves.

Tests: **352 Flutter + 138 backend, 0 analyzer issues.**

## 25. Owner review round 9 (July 2026) — verification precision & habits UX

**Meal identity: a breakfast can no longer tick "Dinner".** The reported bug: a
no-target diet habit passed on ANY food logged that day — the rule had no
concept of WHICH meal. Three-layer fix: (1) `FoodEntry` now carries an
**eaten-at time** (manual logs stamp "now"; Google imports parse it from the
nutrition-log interval, plus Google's own `meal_type` label) — shown on each
diet row; (2) the **AI verifier now judges no-target diet habits** (meal
identity is semantic, exactly like which-workout-counts) with a new MEAL
IDENTITY prompt rule — meal windows, "a breakfast entry NEVER satisfies a
dinner habit", time-less entries can only satisfy generic eating habits, and
no-eating-after-cutoff semantics; (3) a **deterministic meal-window fallback**
(`mealIdentityMet`) guards the offline path: named meals get their window
(breakfast 04–11, lunch 11–16, dinner 16:30–24), unnamed timed habits get
±3h of their ideal time. Numeric-target diet habits (protein ≥ 150 g) stay
exact-rule — the LLM still can't out-compute a total.

**Habits screen, decluttered.** The TODAY card is just x/y done + the bar (the
roster below IS the "still to do" list); the summary stats are now **TIME/DAY +
TIME/WEEK** (`weeklyScheduledMins` — duration × due-days/week, ÷7 for the day
average) instead of time/month + habit count; and the **"choose one" preset
grid is gone**: you type anything, and `inferPreset` silently matches the title
against the preset knowledge base — a title naming a known quantity ("sleep
score 80+", "protein", "steps") adopts its exact data wiring (linked metric /
goal key, with the default target suggested into an empty field), everything
else is AI-judged (workout/diet) or tick-only, with a live hint line showing
which. The timeline now computes **column layout from VISUAL spans** (min
32-min block), so a min-height short habit can never be drawn over the next
one, and ≤20-min habits render as compact `HH:MM · title` chips.

**AI: current models + the coach truly sees everything.** Defaults upgraded to
the best-per-tier GA models (July 2026): `gemini-3.1-pro` (chat/planner/
digest/verification) + `gemini-3-flash` (nudges/nutrition — cheaper AND
stronger than the old 2.5-flash); Gemini-3-family flash gets
`thinkingLevel: low` (2.x keeps `thinkingBudget: 0`), and the 404→fast-model
degrade still guards unavailable ids. Context fixes: the **aesthetics section
had been silently EMPTY** since aesthetics moved tracked→ranked (a stale tier
filter) — the coach sees them again; **meals now carry eaten-at times** (meal
timing is coaching signal, and the system prompt says so); the **energy series
uses the honest burn estimate** (BMR × 1.2 + workouts — raw BMR told the coach
every day was a surplus); habit context gains **90-day adherence** alongside
30-day, plus cadence/days/time/created — the coach's habit memory is now:
adherence 90 days, streaks to 90 due-days, metric history 730 days
(180 pts/metric), meals 14 days, sets 20 sessions, verdicts backed up 180 days.

**Aesthetics audit — verified sound, one real bug found (the context one
above).** Per-path status: **skin/oral** classical-CV composites with
tone-robust signals (variance-based redness patchiness, luminance CV) and
guard rails (raises when <5% skin pixels / no teeth found), anchors unit-tested
(`test_photo.py`); **hair** macro-photo strand counting with user-calibrated
FOV (density scales with FOV, tested); **eye** tumbling-E with credit-card
px/mm calibration + correct 5×MAR optotype math + screen-resolution floor,
helpers unit-tested; **ear** ascending pure-tone ramp, honestly framed as
uncalibrated dBFS screening; **voice** Praat jitter/shimmer/HNR + AVQI v03.01
(vowel-only, flagged) with silence rejection — and the sheet REFUSES to log
when AVQI fails rather than popping the /100 composite into the AVQI-ranked
metric; **grooming** a weighted structured self-rating, framed as such. All
seven flagged provisional in the UI; none feed the overall rank headline
beyond the aesthetics category's 0.15 weight.

Tests: **358 Flutter + 139 backend, 0 analyzer issues.**

## 25b. Theme perfection (July 2026)

The Material layer is now themed ONCE in `main.dart`'s `buildPhysicalTheme()`
so no stock-M3 widget can leak into the near-black look:

- **surfaceTint disabled everywhere** (appbar/cards/dialogs/sheets/menus/
  pickers) — M3's seed-colour wash on elevated dark surfaces was the single
  biggest "cheap dark theme" artifact; depth now comes from explicit colours,
  borders and glows. `scrolledUnderElevation: 0` also kills the appbar tint
  flash when content scrolls beneath it.
- **Every popup surface matches the hand-built screens**: dialogs (card tone,
  r20), bottom sheets (sheet tone, top-r20, themed drag handle), date & time
  pickers (previously stock purple — used by DOB + habit times), popup menus,
  floating snackbars (raised tone, r12).
- **Inputs themed once**: rounded-12 fields, faint border, accent focus ring,
  muted labels/hints/helpers — and every screen's explicit
  `border: OutlineInputBorder()` override was stripped (18 call sites) so all
  TextFields actually inherit it.
- **All 18 modal sheets unified**: explicit per-call `backgroundColor`/`shape`
  args removed (they spanned four different surface colours); every sheet now
  inherits the same themed surface.
- **Chips, tab bar, buttons, FAB, progress, selection** all themed (no M3
  checkmark chips, label-sized tab indicator with no full-width divider,
  rounded w800 buttons); edge-to-edge system UI with light status/nav icons.
- Verified visually via a temporary golden-render harness (home / progress /
  habits / diet / dialog screenshots), then removed.

## 25c. Sets exist ONLY inside imported exercises (owner correction, July 2026)

The round-8 "pre-log holder" read the owner's intent wrong. The actual rule:
**a set cannot exist outside a Google-imported (watch) exercise — you only
create sets from inside one.** Shipped: `createSession`/`createFromTemplate`
are DELETED from `WorkoutNotifier` (no code path mints a standalone workout);
the Exercise FAB, template chips, Today's Plan and the Habits tab's
"start planned workout" all route through one shared
`openTodaysWatchExercise(…, {plan})` — it opens today's watch exercise (chooser
when several), drops a plan's blank set slots INTO it, and when none exists yet
it says to record with the watch and sync (no holder is created). The
"WAITING FOR THE WATCH EXERCISE" strip is gone. Today's-Plan "done" now means
today's watch exercise contains one of the plan's exercises (the old
title-match broke once plans applied into the watch session). The
link/absorb machinery stays solely as MIGRATION for legacy holders arriving
from old backups via `repoMerge`; tests reframed accordingly.

## 25d. Habit archive — the coach never forgets (July 2026)

**Deleting a habit now RETIRES it instead of erasing it.** `deleteHabit` used
to purge the habit + its completions + its AI verdicts in one stroke — the
coach forgot the habit ever existed and past days lost their roster. Now
`Habit.archivedAt` marks retirement: the first delete archives (identity +
completions + verdicts all stay; no tombstone), a second delete on the
archived habit purges for real (tombstoned).

**One rule drives every view**: `isDueAndActive` = due AND createdAt ≤ day <
archivedAt. Archived habits therefore vanish from today's roster, reminders,
Calendar (their events auto-prune on the next push), verification and the
planner — but still appear, with their true done/missed state, when browsing
the past days they lived on (day view, week view, heatmap, adherence).
Archived tiles are read-only with a 🗄 pill; long-press shows the story with
"Delete forever" as the purge.

**The coach's habit memory, spelled out:** active habits now carry
`recent_days` — the last 14 due days as a ✓/×/– pattern string — plus 30-day
and 90-day adherence, streaks (90-day horizon), schedule and creation date;
archived habits (newest 20) ride every request as `archived: true` entries
with created/archived_on and lifetime due/done/adherence over their active
window (≤365 d). The system prompt instructs: archived = reference/history
("you used to…"), never an active commitment. Archival propagates one-way
across devices via the backup merge (an old snapshot can't resurrect a
retired habit as active).

Full AI-memory windows after this round: habits — completions kept forever
locally, 90-day adherence + 14-day patterns + archived lifetime stats sent
per request, AI verdicts backed up 180 days; metrics — 730 days
(180 pts/metric); meals 14 days (with times); workout sets 20 sessions;
pins always.

## 26. Owner review round 10 (July 2026) — the presentation pass

**Body graph redrawn.** The prototype-ported blocky figure (rectangular slab
silhouette, floating muscle quads) is replaced by an athletic male outline —
head/neck/trap slope, deltoid caps, arms hanging with a real gap from a
V-tapered torso, narrow waist, hip flare, knee/calf taper, feet — authored
right-side and mirrored exactly about x=74 (`gen_body.py` scratch generator),
with every muscle poly re-placed to fit (pec fans with a delt gap, 6-cell abs +
inert obliques, quad sweep/teardrop pairs, trapezius kite + lats V + inert
erectors on the back, gastrocnemius heads). Inner-figure hands/shins/feet
re-seated to the new limbs. Iterated visually via a golden-render harness
(deleted after use; goldens are platform-sensitive).

**Darker, cohesive theme.** All nine dark tokens shifted down one step in a
single consistent map (screen 0xFF08091A→0xFF04050C, cards
0xFF12152E→0xFF0D1024, etc.) across every screen + the Material theme — deeper
blacks make the tier glows carry the UI.

**The energy graph explains itself.** An ⓘ on the ENERGY TREND card opens a
plain-language sheet: IN = logged food; OUT = watch total or BMR×1.2+workouts
estimate; NET = IN−OUT; ~7,700 kcal ≈ 1 kg so avg-net×7÷7700 = expected
kg/week; the weight strip is the ground truth to trust when they disagree;
gaps are unlogged days, excluded from the averages.

**Every metric says HOW to log it.** `MetricDef.howTo` — a one-line protocol
(equipment, form standard, what number to enter) — shown as a 📝 card in the
detail sheet beside the 📍 movement line, for all 24 ranked non-aesthetic
metrics + bodyweight/height (aesthetics keep their richer measurement guides).

**Deep rank research (web-grounded).** Every distribution checked against
published norms: FRIEND registry pins VO₂max men-20s median at exactly 48
(app: N(48,9) ✓); NHANES-era RHR ~70-72 ✓; RMSSD 40-80 ms young adults ✓
(lognormal median 50 spans it); vertical jump ~43-45 cm ✓; untrained 100 m
15-17 s ✓; recreational-male 5k 33-35 min vs the app's general-pop 35-min
median ✓; HRR average 15-26 bpm (Apple real-world mean 26) ✓; strength
trained-tail medians land on published intermediate standards (bench 1.15×,
squat 1.6×, deadlift 2.0×, OHP 0.7×BW) ✓. Two fixes shipped: **plank**
median 80→65 s (strict-form genpop holds cluster 20-60 s — a 60 s hold ranked
below the middle) and **deadhang** median 60→50 s (60 s is "good", not
average). US NHANES young-male body fat (~23-25%) runs above the app's 20±6
global compromise — kept deliberately, noted here. Goldens regenerated;
Python⇄Dart parity re-proven.

Tests: **358 Flutter + 139 backend, 0 analyzer issues.**

## 27. Owner review round 12 (July 2026) — the coach can query history on demand

The final robustness gap: the coach's context is a *summary* (downsampled
730-day history, last-14-days meals, 20 recent set sessions), so questions
about a specific period — "was I more consistent last March?", "what did I
eat the week I plateaued?" — used to get answered from thin air. Now the
model has a **read-only `query_history` tool** and is instructed to gather
before answering, never to guess at history it could look up.

**Architecture — the app answers its own coach's questions.** The backend
holds no user data, so the tool round-trips through the device:

1. `/me/coach/chat` declares `QUERY_TOOLS` (alongside the action tools) and
   returns any validated `query_history` calls to the app as
   `CoachChatOut.queries` (reply is interim, actions deferred).
2. The app resolves each call locally — `coachQueryResult` in
   `coach_context.dart`, pure + unit-tested — and re-posts with
   `tool_events: [{text, calls, results}]`.
3. The router replays each event as a paired functionCall/functionResponse
   turn (`tool_event_turns` → `_turn_parts` in the Gemini client) and the
   model continues with real data.

Topics: `metric` (full-resolution daily values — the context history is
downsampled, this is not), `habit` (day-by-day ✓/× for one title,
**archived habits included** — the archive round's memory is now queryable),
`meals` (foods + eaten-at times per day), `workouts` (sessions with
per-exercise sets/volume). Guardrails at every layer: topics/dates validated
and clamped server-side (≤366 days, reversed ranges swapped, ≤4 calls per
round); `MAX_QUERY_ROUNDS = 3`, after which the query tool is withheld so a
looping model must answer in text; unknown ids answer with the *real* metric
ids / habit titles so the model self-corrects in the next call; app-side
caps (150 meal entries, 40 sessions), future ends clamped to today; a failed
device lookup becomes `{'error': …}`, never a crashed reply; results pass
the same `scrub_pii` as the main context (free-text names must not become a
scrub bypass). Transparency: each lookup is shown in the thread as a muted
"🔎 Looked up …" line, the typing bubble says what's being checked, and the
"What I see" sheet's privacy note discloses the capability.

**Formatter honesty audit (bug fix).** The system prompt told the model about
fields the backend formatter silently dropped — the model was instructed to
read data it never received: `_habit_lines` ignored `recent_days` (the
14-day ✓/×/– pattern), `adherence_90d`, schedule (weekly days/time/created)
and EVERY archived field, so retired habits rendered exactly like active
ones and inflated the done-today denominator; `_meals_lines` dropped the
eaten-at time the prompt calls "real signal". Now: active habits render
pattern + both adherence scales + schedule; archived render as
`🗄 title RETIRED (created → archived_on · done/due days · N% lifetime)`;
the header counts active only ("2/5 active done today; 3 retired shown as
history"); meals lead with their time; the transparency sheet marks
archived (`🗄 … · retired <date>`). The planner prompt gained rule 5:
retired habits are history — learn from their lifetime adherence, don't
quietly re-propose them. Rule of the round: **a prompt may only reference
fields a test proves the formatter renders.**

Tests: backend — query validation (malformed/reversed/oversized), replay-turn
pairing incl. the PII scrub, Gemini part encoding, the two-round chat
round-trip, the round-cap tool withholding, habit/meal formatter rendering;
Flutter — `coachQueryResult` per topic incl. archived-habit adherence,
last-per-day metric collapse, unknown-id self-correction payloads, range
guards.

## 28. The dead-calendar-grant trap (July 2026 hotfix)

User report: "calendar imports stopped working; the Calendar button says
connect first, but everything shows synced." No calendar code had changed —
the cause was TIME, not a commit: Google testing-mode refresh tokens die
after 7 days, and the app had a state trap for exactly that case.

**The trap.** `/me/calendar/push` correctly failed with 401 needs_reconnect
when the stored calendar refresh token was dead — but
`/integrations/google/status` reported `calendar_connected: true` because it
only checked that a token ROW existed. So the error said "connect in the ☁
sheet" while the sheet hid the Connect button and showed everything green.
No path out.

**Fixes.**
- `calendar_token_usable()` — status now validates the token can actually
  mint an access token. A dead grant (`invalid_grant`) reports
  `calendar_connected: false`, so the Connect button reappears exactly when
  it's needed. A transient refresh blip still reports connected (no
  reconnect-nagging over a network hiccup).
- The push distinguishes the two failures: `invalid_grant` → 401
  needs_reconnect; transient refresh error → 502 "try again" (it used to
  send users to a re-consent that fixed nothing).
- The silent launch auto-sync — the only calendar push many users ever run —
  now surfaces a dead grant as a snackbar instead of failing invisibly, and
  the Habits-tab error names the real cause ("your Google Calendar link
  expired").

**Archive-round follow-ups caught in the same sweep** (retired habits are
kept as history since §25d, and three calendar paths didn't know):
`/me/calendar/push` and `build_ics` now skip `arch` habits (the push also
prunes their existing events via the reconcile pass); the cloud sheet's
connect-flow pushes the ACTIVE roster (it pushed archived ones, resurrecting
retired habits as events right after connecting); and cloudSync's mirror
gates on the whole roster but pushes the active list — archiving your last
habit now clears its events instead of stranding them.

Tests: dead-grant 401 vs transient 502; validated `calendar_connected`
(fresh token = no refresh round-trip, dead = false, blip = true); archived
habits never written + their events pruned; ICS skips archived.

## 29. Final QA sweep (July 2026) — archived habits are untouchable by title

A last full-app audit of every raw `habits` read found one bug class left:
title-matched and loop operations could land on ARCHIVED habits, where a
"remove" is a permanent purge and an edit resurrects. Four fixes:
`adjustTarget` matches active habits only (it rebuilt the match without
`archivedAt` — the coach retuning "Protein" could silently resurrect a
retired era of the same name); the planner's "Replace my current habits"
retires the active roster only (it swept the whole list, purging all
previously-archived history on every replace); the coach's `remove_habit`
action matches active only; and archived tiles are not swipe-dismissable
(a swipe on a history row was a no-confirmation permanent purge — the purge
lives behind the detail sheet's deliberate "Delete forever"). Also verified
in the sweep: every `api_client` path resolves to a registered backend
route, all 11 routers are mounted, the backend byte-compiles, and both
suites + analyzer are green.
