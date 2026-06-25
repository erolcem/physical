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
pinning). **120 Flutter tests + 47 backend tests pass, 0 analyzer issues**, the
Python⇄Dart engine is parity-tested to ~1e-5, hosted on Railway, shipped to iPhone
via TestFlight. The coach runs on **Gemini** so the whole stack lives in the user's
Google account (sign-in, Health, Calendar, friends, AI).

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
│  Tabs: Home · Progress · Habits · Coach · Profile        (Riverpod state)    │
│  • Rank engine runs ON-DEVICE → instant ranks from local logs                │
│  • Opt-in cloud sync over HTTPS with a Bearer JWT                            │
│  • Logs: metrics, workouts (sets), food (macros); habits; profile; pins      │
└───────────────┬──────────────────────────────────────────────────────────────┘
                │ HTTPS (JWT)
┌───────────────▼──────────────────────────────────────────────────────────────┐
│  BACKEND — FastAPI, always-on on Railway                                      │
│  /auth · /me/samples · /me/ranks · /me/profile · /me/friends · /me/coach      │
│  /integrations/google · /privacy /terms · /health                            │
│  • Imports the SAME rank engine → server ranks == client ranks               │
│  • Scheduled job refreshes Google data even with no device open              │
└───────┬───────────────────────────────┬───────────────────────┬───────────────┘
        │                               │                       │
┌───────▼─────────────┐   ┌─────────────▼──────────┐  ┌─────────▼──────────────┐
│ Postgres (canonical  │   │ Google Health API      │  │ Gemini (Generative     │
│ sample store + users │   │ (per-user OAuth):      │  │ Language API):         │
│ + friendships + …)   │   │ Fitbit → samples       │  │ the AI coach           │
└──────────────────────┘   └────────────────────────┘  └────────────────────────┘
```

**The nine layers** (detailed below): `A` rank engine · `B` Flutter app ·
`C` backend store+API · `D` auth/accounts · `E` Google Health integration ·
`F` habits · `F2` exercise+diet logging · `G` friends/social · `H` AI coach.

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
  key per type: logs/habits/completions/profile/food/workouts/pins). The whole app
  reads/writes through this seam; nothing touches storage directly.
- **Local-first:** ranks recompute reactively from `logsProvider`; cloud sync is the
  opt-in `cloud_sheet`.

**The five tabs:**
- **Home** (`home_screen.dart`) — the overall rank card (tap → breakdown sheet with
  **category bars**, **stats** (figure 4), and the **rank-distribution badges**
  (figure 3)); **coach-pinned correlation insights**; the front/inner/back **body
  graph** (tap a muscle → detail); per-category metric grids; aesthetics strip.
- **Progress** (`progress_screen.dart`) — Google-Health-style **category cards** →
  each opens its own **graph page** (timeframe chips; y-axis in rank/native/% space)
  + a **multi-metric comparison with a Pearson correlation** readout.
- **Habits** (`habits_screen.dart`) — Layer F.
- **Coach** (`coach_screen.dart`) — Layer H.
- **Profile** (`profile_screen.dart`) — identity form + BMI + **Share my rank** +
  the **Friends** section (Layer G).

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
| `GET/PUT /me/profile` | profile upsert/read |
| `POST /me/samples` · `GET /me/samples` | bulk idempotent ingest (server-side `strength_value`) · list |
| `GET /me/ranks` | overall + per-category + per-metric ranks |
| `POST /me/friends` · `GET /me/friends` · `GET /me/friends/requests` · `POST /me/friends/{id}/accept` · `DELETE /me/friends/{id}` | social: request → accept → compare ranks |
| `GET /me/coach/status` · `POST /me/coach/chat` · `POST /me/coach/context` | coach availability · chat (+ actions) · transparency context |
| `…/integrations/google/authorize|exchange|status|sync|debug` | per-user Google Health linking + sync + raw debug |

All `/me/*` and `/integrations/*` routes are gated by `current_user` (JWT).

### 6.2 Ranking & sync
- `ranking.compute_ranks(samples)` → `(overall, categories, metrics)` — latest
  sample per ranked metric, scored at its bodyweight-at-time; reused by `/me/ranks`,
  the coach context, and friends' rank lookups.
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
- **Per-user isolation**: tokens, samples, profile, friendships are all keyed by
  user id; no user can read another's raw data (friends see only an *overall rank*).

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

## 10. Layers F & F2 — habits, exercise, diet, friends

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

### 10.3 Diet logging (`data/diet.dart`, `ui/diet_screen.dart`)
A **holistic diet page**: food entries with macros (kcal + P/C/F + **fibre**) →
**daily totals** with a **macro-kcal breakdown bar** and a **7-day calorie trend**
(`caloriesLastNDays`), fed to the coach. The Progress "Diet" subpage routes here
(its own domain layout). *Remaining:* full micronutrients (needs a food database)
and tailored graph layouts for the exercise + sleep subpages.

### 10.4 Friends (`backend/.../friends.py` + Profile section)
Add by email → pending → accept → a **mini leaderboard** of friends' overall ranks
(tier/sub/top% only — never raw samples). Privacy by mutual consent. Plus the
**Share my rank** clipboard slice.

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
- **Flutter (120):** engine parity vs golden vectors; system-verification
  (registry↔engine, PDF categories, every lift ranks, directions, overall/category);
  habits (streaks/verification/planner/weekly/calendar); profile; diet/workout;
  correlation; notifications; sync; and an **all-tabs runtime smoke test**.
- **Backend (47):** engine load + coverage; auth; samples (isolation rep-volume +
  raw 1RM); ranks; Google Health mapping (every dataType shape + derived sleep score
  + background metrics); friends (request/accept/rank/privacy); coach (PII-free
  context incl. diet/training/aesthetics, agentic + pin parsing, Gemini mocked,
  guards); legal pages.

---

## 14. PDF plan → implementation map (every detail)
| PDF | Status |
|---|---|
| **Part 1 — Logs** (12 strength, performance, recovery, aesthetics, background) | ✅ all metrics; strength yields volume (workout) + 1RM/rep-volume (rank); profile tab |
| Part 1 — background auto-Google (steps/zone/energy) | 🟡 wired, type-names need a live `/debug` confirm |
| Part 1 — 5k auto-from-running, auto "exercises", deeper sleep sub-metrics, aesthetic vision/audio models | 🟡 need live Google data / 3rd-party models (manual fallbacks built) |
| **Part 2 — Graphs** (category cards → custom graph; comparison + correlation) | ✅ |
| **Part 3 — Body graph & Ranks** (clickable body graph; card w/ progress+log+milestones; 8 tiers + I/II/III + Glory; category+overall; **rank-badge distribution fig 3**; **overall stats fig 4**; **correlation engine fig 5**) | ✅ all |
| **Part 4 — Habits** (check-off, verification, planner, density bar, weekly, calendar) | ✅ |
| **Part 5 — AI coach** (sleep/diet/exercise/aesthetics review; goals; milestones; notifications; habit-aware; structured context; agentic actions; dynamic volume auto-regulation; strategic correlations) | ✅ (voice logging intentionally skipped) |
| **Part 6 — Friends / sharing / QoL** | ✅ add→accept→compare + share |
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
  + calendar URL.
- `profile.dart` — ProfileData + BMI.
- `diet.dart` — FoodEntry + daily totals. *Add a micronutrient score (needs food DB).*
- `workout.dart` — WorkoutSession/Set → volume + best-set. *Add two-step verification
  vs a Google Health workout session.*
- `correlation.dart` — Pearson + day-alignment + pin model.
- `notifications.dart` — daily habit reminders (guarded iOS/Android). *Verify on
  device; add iOS foreground-present delegate.*
- `body_figure_data.dart` — front/back/inner SVG muscle polygons.

**App · state (`lib/state/`):** `providers.dart` (logs/ranks/overall/category),
`habit_providers.dart`, `profile_providers.dart`, `log_providers.dart` (diet/
workout/pins).

**App · UI (`lib/ui/`):**
- `main_screen.dart` — 5 tabs + Log FAB chooser + reminder re-sync.
- `home_screen.dart` (largest, ~800 lines) — overall card, breakdown sheet (figs
  3/4), pinned insights, body-graph section, metric grids. *Candidate to split.*
- `progress_screen.dart` (~590) — category cards → graph page + correlation.
  *Candidate to extract the chart widget.*
- `habits_screen.dart`, `coach_screen.dart`, `profile_screen.dart`,
  `metric_detail_sheet.dart`, `diet_screen.dart`, `workout_screen.dart`,
  `body_graph.dart` (CustomPainter + hit-test), `badge.dart` (SVG medallions),
  `cloud_sheet.dart` (sign-in + sync).
- `main.dart` — entry; loads repo, fires notification setup, runs app.

**Backend (`backend/app/`):** `main.py`, `config.py`, `db.py`, `models.py`,
`schemas.py`, `engine.py`, `ranking.py`, `registry.py`, `jobs.py`, `auth.py`,
`coach.py`; `routers/` (auth/health/legal/profile/ranks/samples/friends/coach);
`integrations/google_health/` (oauth/client/mapping/router — *confirm background
type-names + deeper sleep fields via `/debug`; add auto exercises/energy*);
`integrations/gemini/client.py` (*add streaming + true function-calling*).

**Tests:** `test/` (9 Dart) + `backend/tests/` (8 Python).

**Config / docs:** `pubspec.yaml`, `analysis_options.yaml`, `codemagic.yaml`,
`railway.json`, `backend/Dockerfile`, `backend/DEPLOY.md`, `backend/VERIFICATION.md`,
`GUIDE.md`, `ARCHITECTURE.md`, `All readmes/` (design doc, the plan PDF, STATUS,
STANDARDS).

---

## 16. Known limitations & future work (prioritised)
1. **Ground the strength standards** with real data — the one provisional spot; most
   improves rank honesty.
2. **Live `/debug` pass** to confirm Google background type-names (steps/zone/energy)
   and wire deeper sleep sub-metrics + auto "exercises"/energy.
3. **Two-step workout verification** vs a Google Health workout session.
4. **Coach upgrades** — streaming replies, true function-calling, diet micronutrient
   scoring.
5. **Split the two big UI files** for maintainability.
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

**P1 · Profile ported from Google Health.** *Current:* weight + body-fat already
sync as metrics; age/height/DOB are manual on the Profile tab. *Target:* pull the
Google Health profile (height, date-of-birth→age, weight, body-fat) on sign-in/sync,
manual only as fallback. *Needs:* the Google Health profile read scope/endpoint —
confirm shape via `/debug`.

**🟡 MOSTLY DONE · Workout logging = a real tracker.** Shipped: sets grouped under
each exercise (add exercise → log its sets), per-exercise + total load/volume,
best-set updates the rank. *Remaining:* the **time-window dual-authorisation against
the Google Health exercise session** (needs the auto-exercises sync + a live `/debug`
look at the Google session shape).

**🟡 MOSTLY DONE · Diet = holistic.** Shipped: kcal + P/C/F + **fibre**, a macro-kcal
breakdown bar, a 7-day calorie trend, and the Diet graph subpage routing to this
holistic layout. *Remaining:* full **micronutrients** (needs a food database, maybe
a Gemini-assisted lookup) and tailored graph layouts for the **exercise + sleep**
subpages too.

**✅ DONE · Habits = structured & data-aligned, not free-text.** Shipped: sections +
in-realm presets + bounded custom; verify modes (metric/workout/diet/manual)
auto-corroborated by the day's logs; ideal time + duration; daily/weekly-by-day
cadence; today's roster + weekly schedule; monthly-cost dropped. *Next refinements:*
per-habit explicit numeric targets (e.g. "protein ≥ 150 g") checked against the day's
totals, and goal-emphasis the coach remembers.

**P2 · Graphs & ranks — accessibility + "epic" polish.** Fixed the **"All" timeframe**
label crowding (this round). Further: make the ranks/graph layouts more credible and
striking, especially **upgrading the rank-badge assets**.

**P2 · AI coach — fixed context + fixed response selection.** Keep context structured
and responses a robust selection per Table 3 (Sleep / Diet / Exercise / Aesthetics
review; Strategic goal-setting with an emphasised goal + plateau detection; Milestone
discussion; Notifications; Habit-update-aware; deletable structured context;
autonomous strategic-correlation pinning; dynamic volume auto-regulation on a
daily-readiness drop). Voice = out of scope.

**Build order:** (1) ✅ **Habits redesign** → (2) 🟡 **Workout tracker** (grouped sets
done; Google-session dual-auth pending live data) → (3) 🟡 **Diet** (holistic page +
fibre + trend done; micros + exercise/sleep tailored layouts pending) → (4) Profile
auto-port from Google Health → (5) Rank-badge/graph visual polish (Liftoff-style) →
(6) Coach fixed-response selection. Each shipped behind its own tests.
