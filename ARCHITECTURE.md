# Physical — Architecture

A complete map of the system: every layer, how data flows, and where each feature
from the plan lives. Companion to `GUIDE.md` (usage), `backend/DEPLOY.md` (hosting),
`backend/VERIFICATION.md` (Google review), and `All readmes/` (the design docs + PDF).

**Status:** the **entire plan (Parts 1–7, AI coach included)** is implemented,
including the complex exercise + diet logging and the coach's agentic actions,
dynamic volume auto-regulation, context transparency, and correlation pinning.
120 Flutter tests + 47 backend tests green, 0 analyzer issues, Python⇄Dart engine
parity to ~1e-5. Hosted on Railway; iPhone via TestFlight. The coach runs on
**Gemini** to stay in the user's Google ecosystem.

---

## 1. The vision (one sentence)
Measure every trainable dimension of the body, rank each **honestly** against the
general young-male population as tiered ranks on a body graph, hold the user
accountable with a habits layer, and (future) coach them with AI over all of it —
*a rank must be honest or the gamification collapses.*

---

## 2. Layered architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  CLIENT — Flutter app (local-first; iOS + Linux/Android/web dev)       │
│  Home · Progress · Habits · Coach · Profile  (Riverpod state)          │
│       │ ranks computed on-device by the Dart engine                    │
│       │ opt-in cloud sync (Bearer JWT)                                 │
└───────┼────────────────────────────────────────────────────────────────┘
        │  HTTPS
┌───────▼────────────────────────────────────────────────────────────────┐
│  BACKEND — FastAPI on Railway (always-on)                              │
│  /auth (Google Sign-In) · /me/samples · /me/ranks · /me/profile       │
│  /integrations/google · /privacy /terms · /health                     │
│  imports the SAME rank engine → server ranks == client ranks          │
└───────┬───────────────────────────────────┬────────────────────────────┘
        │                                    │
┌───────▼─────────────┐          ┌───────────▼───────────────────────────┐
│  Postgres (canonical │          │  Google Health API (per-user OAuth)   │
│  sample store)       │          │  Fitbit → Google Health → samples     │
└──────────────────────┘          └───────────────────────────────────────┘
```

### Layer A — Rank engine (the core, dual-implemented)
The honest-ranking math, written **once and ported**, kept in lockstep by golden
vectors:
- `lib/engine/physical_rank_engine.py` — canonical reference (also imported by the
  backend, so server ranks match the client byte-for-byte).
- `lib/engine/rank_engine.dart` — faithful Dart port for on-device ranking.
- Parity proven by `test/golden_vectors.json` + `test/rank_engine_test.dart` (~1e-5).

What it does:
- **Allometric bodyweight scaling** — strength scored as `value / BW^0.67`.
- **Distribution → percentile** via CDF (normal / lognormal / two-component
  mixture), with an explicit **lower-is-better `direction`** flag.
- **Derived tier thresholds** (never hand-typed) — `Wood→Bronze→Silver→Gold→
  Platinum→Diamond→Champion→Titan→Glory` at population top
  `99/80/60/40/20/10/3/1/0.1%`, each split into sub-ranks **I/II/III**.
- **Two-component mixture strength standards** (untrained mass + trained tail).
- **Bodyweight-at-time** — a lift is scored against the weight when it was lifted
  (snapshotted, immutable), so past ranks never silently shift.
- **Rep-volume-at-load** for isolation lifts (weight × reps), instead of an
  unreliable 1RM estimate, via the shared `strength_value`/`strengthValue`
  dispatcher.
- **z-space overall + per-category** ranks.

### Layer B — Flutter app (local-first client)
- **State:** Riverpod. Storage seam: the `Repository` interface (in-memory for
  tests/default, `PersistentRepository` via `shared_preferences` on device).
- **Local-first:** ranks compute on-device from logs; the cloud is opt-in mirror.
- **Screens (5 tabs):**
  - **Home** (`home_screen.dart`) — overall rank card (tap → category
    breakdown sheet), front/inner/back **body graph** (`body_graph.dart` +
    `body_figure_data.dart`, tap a muscle → detail), and per-category metric grids.
  - **Progress** (`progress_screen.dart`) — Google-Health-style category cards →
    per-category graph page (timeframe control, rank/native/% y-axis) + a
    multi-metric **comparison with Pearson correlation**.
  - **Habits** (`habits_screen.dart`) — see Layer F.
  - **Coach** (`coach_screen.dart`) — AI chat, see Layer H.
  - **Profile** (`profile_screen.dart`) — age/gender/height/weight/body-fat + BMI,
    **Share my rank**, and **Friends** (Layer G).
  - **Metric detail sheet** (`metric_detail_sheet.dart`) — rank, derived **tier
    ladder**, log history, inline log form; provisional metrics flagged.
  - **Rank badges** (`badge.dart`) — metallic SVG medallions.
  - **Cloud sheet** (`cloud_sheet.dart`) — Sign in with Google + Sync.

### Layer C — Backend (FastAPI canonical store + rank API)
`backend/app/` — FastAPI + SQLAlchemy 2.0, runs on **SQLite (dev/tests)** and
**Postgres (prod)**; schema is DB-agnostic and auto-creates on startup.
- **Imports `physical_rank_engine.py` directly** (`app/engine.py`) — single source
  of truth, no drift.
- **Routers:** `health`, `legal` (`/privacy`,`/terms`), `auth`, `profile`,
  `samples`, `ranks`, `friends`, `coach`, and the Google Health integration.
- **Canonical `sample`** keyed by user, idempotent dedup on
  `(user, metric, source, source_id)`; server-side `strength_value` from raw
  `{weight, reps}`.
- **Scheduled sync** (`app/jobs.py`, `python -m app.jobs`) refreshes every
  connected user's Google data so it's fresh even with no device open.

### Layer D — Auth & accounts (one Google authorization = identity + health)
`backend/app/auth.py` + `routers/auth.py` + `integrations/google_health/oauth.py`:
- **Google Sign-In** carries `openid/email/profile` **and** the Google Health
  scopes, so one consent creates the account (keyed by Google `sub`) **and** links
  the data source.
- Backend issues a **JWT** (`HS256`); every `/me/*` and `/integrations/*` route is
  gated by `current_user`. The app persists the JWT (remembered across launches).
- Per-user isolation: tokens + samples are scoped to the user id; no user sees
  another's data.

### Layer E — Integrations (Google Health, per-user)
`backend/app/integrations/google_health/`:
- `oauth.py` (consent URL + token exchange/refresh), `client.py` (v4 dataType
  query), `mapping.py` (dataPoints → canonical samples with tolerant extractors),
  `router.py` (authorize/exchange/status/sync/debug + the reusable `sync_user`).
- Pulls resting-HR, HRV, VO₂max, bodyweight, body-fat, sleep (→ duration /
  efficiency / deep / REM / **derived sleep_score**), plus background steps /
  active-zone / energy.

### Layer F2 — Exercise + diet logging (PDF Part 1, the "big" data types)
- **Workout** (`data/workout.dart` + `ui/workout_screen.dart`): a session is a dated
  list of sets → total **volume** + the **best set per exercise**, which updates that
  lift's rank (1RM/rep-volume). Rollups (volume/sessions/muscles over 7d) feed the AI.
- **Diet** (`data/diet.dart` + `ui/diet_screen.dart`): food entries with macros →
  **daily totals** (energy/protein/…), fed to the AI.
- Both local-first (own storage keys) via `state/log_providers.dart`; reached from
  the **Log** FAB (Metric / Workout / Food).

### Layer F — Habits (accountability + planner, Phase 2)
`lib/data/habits.dart` (pure logic) + `state/habit_providers.dart` + the Habits tab:
- **Accountability:** daily check-off, streaks (today-or-yesterday aware),
  **two-step verification** (`statusFor` — a tick corroborated by a same-day log of
  a linked metric → "verified"), today's X/Y summary, and a **weekly history**
  (last-7-days bar chart + per-habit dot strip).
- **Planner/budgeter** (kept from the prototype): category (Strength/Performance/
  Sleep/Diet/Aesthetics/Other), time, duration, monthly cost, a **time/$ rollup**
  and **24h density bar**.
- **Calendar push:** one-tap "Add to calendar" → Google Calendar daily event
  (`googleCalendarUrl`, via `url_launcher`).

### Layer G — Friends / social (PDF Part 6)
`backend/.../friends.py` + the Profile tab's Friends section:
- Add a friend **by email** → pending request → **accept** → both can see each
  other's **overall rank only** (tier/sub/top% — never raw samples), a mini
  leaderboard sorted by rank. Privacy is by mutual consent (`pending|accepted`).
- Plus the **Share my rank** clipboard slice. Friends require sign-in.

### Layer H — AI coach (PDF Part 5)
`backend/app/coach.py` + `routers/coach.py` + `integrations/gemini/client.py` +
the **Coach tab** (`coach_screen.dart`):
- On **Gemini** (Flash) to stay in the user's Google ecosystem; key from Google AI
  Studio via `GEMINI_API_KEY` (the app owner's). Cheap + fast.
- `/me/coach/chat` builds a **PII-scrubbed** context from the user's real data —
  overall/category ranks, weakest/strongest metric, recent recovery readings (its
  canonical store) plus the app-supplied **habits + profile** — and a system prompt
  that enforces *coach-not-clinician* framing and "ground every claim in the data".
- The Coach tab is a chat (bubbles, suggested prompts, typing indicator) that sends
  the live habits/profile each message; `/me/coach/status` gates a clean
  "not configured" notice. Requires sign-in.
- **Agentic actions** (with confirmation): the coach emits fenced ```action JSON
  blocks; `parse_actions()` safely extracts/sanitises them; the app renders each as
  an **Apply** card (add/remove habit) that runs through the habits notifier —
  nothing changes without the user's tap. **Dynamic volume auto-regulation**: poor
  recovery → the coach proposes easing the plan.
- **Transparency** (`/me/coach/context` + "What I see" sheet): the exact PII-free
  context shown as labelled sections (profile / ranks / weakest-strongest / recent
  readings / habits) so the user sees precisely what is and isn't shared.
- **Proactive notifications** (`data/notifications.dart`): a daily local reminder
  per timed habit (flutter_local_notifications + timezone), pure reminder logic
  unit-tested, scheduler guarded to iOS/Android (no-op elsewhere), re-synced on any
  habit change.
- **Strategic correlations** (`data/correlation.dart`): the coach can `pin_correlation`
  a metric pair; the dashboard's *Coach insights* computes Pearson r from local logs.
- The coach context also includes today's **diet**, last-7d **training**, and **aesthetics**.

---

## 3. Data model

**Three tiers** (drives everything):
1. **ranked** — has an engine standard → gets a tier, shown on the body graph and
   feeds overall/category ranks (12 strength lifts, 7 performance, 3 recovery).
2. **tracked** — aesthetics; graphed but **never ranked** (no defensible
   population distribution — a deliberate wellbeing choice; enforced in code).
3. **background** — AI-context only (steps, HR, sleep sub-metrics, diet, etc.).

The registry `lib/data/metrics.dart` is the single source for the app; the backend
mirrors the ranked set in `app/registry.py`. The canonical **sample**
(`metric_id, ts, value, bodyweight_at_ts, source, source_id`) is the bridge format
between app logs and Google data.

---

## 4. Data flow

**Manual log → rank:** user logs in a detail sheet → `Repository.saveLog` (local) →
Riverpod recomputes ranks on-device via the Dart engine → body graph + cards update.

**Opt-in cloud sync:** Cloud sheet → `performSync` pushes canonical samples to
`/me/samples`; `cloudSync` triggers a Google pull then merges new samples back into
the local store.

**Google Health (server-side):** `/integrations/google/sync` (or the scheduled
`app.jobs`) → refresh token → `client.query` per dataType → `mapping.to_samples`
→ dedup-ingest into Postgres → available to `/me/ranks` and the next app sync.

---

## 5. Deployment
- **Backend:** Docker image (`backend/Dockerfile`, built from repo root so the
  shared engine is bundled) → **Railway** (`railway.json` pins the Dockerfile) with
  managed Postgres + a cron service for `app.jobs`. See `backend/DEPLOY.md`.
- **iPhone:** **Codemagic** cloud-Mac build → **TestFlight** (`codemagic.yaml`,
  bakes in `BACKEND_URL`). See `GUIDE.md`.
- **App backend URL:** defaults to the hosted Railway URL; override with
  `--dart-define=BACKEND_URL=…` for local backend dev.

---

## 6. File layout (condensed)
```
lib/
  engine/   physical_rank_engine.py · rank_engine.dart        (the math, parity-tested)
  data/     metrics.dart · body_figure_data.dart · habits.dart · profile.dart
            repository.dart · persistent_repository.dart · sync.dart · api_client.dart
  state/    providers.dart · habit_providers.dart · profile_providers.dart
  ui/       main_screen · home_screen · progress_screen · habits_screen · profile_screen
            metric_detail_sheet · body_graph · badge · cloud_sheet
backend/app/
  main.py · config.py · auth.py · db.py · models.py · engine.py · registry.py · jobs.py
  routers/  auth · health · legal · profile · ranks · samples
  integrations/google_health/  oauth · client · mapping · router
test/ (Flutter) + backend/tests/ (pytest) + test/golden_vectors.json
```

---

## 7. Tests (167 total)
- **Flutter (120):** engine parity vs golden vectors, system-verification
  (registry↔engine, PDF categories, every lift ranks, directions, overall/category),
  habits (streaks/verification/planner/weekly/calendar), profile, sync, and an
  **all-tabs runtime smoke test** (now 5 tabs incl. Coach).
- **Backend (47):** engine load + coverage, auth, samples (incl. isolation
  rep-volume + raw 1RM), ranks, Google Health mapping (every dataType shape +
  derived sleep score + background metrics), friends (request/accept/rank/privacy),
  coach (PII-free context + chat with Gemini mocked + guards), legal pages.

---

## 8. Plan → implementation map (non-AI)
| PDF part | Status |
|---|---|
| 1 — Logs (Table 1 metrics, 3 tiers) | ✅ (background sync: steps/active-zone/energy wired; deeper sleep sub-metrics pending live fields) |
| 2 — Graphs (category cards + comparison/correlation) | ✅ |
| 3 — Body graph & Ranks (tiers, sub-ranks, Glory, overall/category, correlation) | ✅ |
| 4 — Habits (check-off, verification, planner, density, weekly, calendar) | ✅ (calendar via Google Calendar link) |
| 5 — AI coach | ✅ Gemini coach over the user's real (PII-scrubbed) data |
| 6 — Friends / sharing / QoL | ✅ add-by-email → accept → compare overall ranks + share |
| 7 — Underlying mathematics | ✅ (exceeds the doc) |
```

---

## 9. File map (every file: what it does · what to improve)

**Engine — the honest-ranking core (must stay in parity)**
- `lib/engine/physical_rank_engine.py` (canonical) — distributions, CDF→percentile, tiers, mixture strength standards, `strength_value`, `est_1rm`. *Improve: ground the untrained/trained medians + isolation anchors with real data (the one soft spot).*
- `lib/engine/rank_engine.dart` — faithful Dart port. *Improve: edit only in lockstep with the .py; golden vectors guard drift.*

**App · data (`lib/data/`)**
- `metrics.dart` — THE metric registry (id/label/category/tier/unit). *Improve: add/edit metrics here; everything is generated from it.*
- `repository.dart` — storage seam (interface + InMemory + demo seed). *Improve: the one place to add a new stored type.*
- `persistent_repository.dart` — shared_preferences impl (per-type keys). *Improve: add a `v2` migration if a model's JSON changes.*
- `sync.dart` — cloud sync + `kBackendUrl` + `apiClientProvider`.
- `api_client.dart` — all backend HTTP calls (auth, samples, ranks, google, friends, coach). *Improve: centralise error→message mapping.*
- `habits.dart` — Habit model + streaks + verification + planner (category/time/duration/cost) + density + weekly + calendar URL.
- `profile.dart` — ProfileData (age/gender/height/weight/bodyfat + BMI).
- `diet.dart` — FoodEntry + daily totals. *Improve: micronutrient/gut-health score (needs a food DB).*
- `workout.dart` — WorkoutSession/Set → volume + best-set. *Improve: two-step verification vs a Google Health workout session.*
- `correlation.dart` — Pearson + day-alignment + pin model.
- `notifications.dart` — daily habit reminders (guarded iOS/Android). *Improve: verify on-device; foreground-present delegate on iOS.*
- `body_figure_data.dart` — front/back/inner SVG muscle polygons (ported).

**App · state (`lib/state/`)** — Riverpod notifiers
- `providers.dart` (logs, ranks, overall/category), `habit_providers.dart`, `profile_providers.dart`, `log_providers.dart` (diet, workout, pins).

**App · UI (`lib/ui/`)**
- `main_screen.dart` — 5 tabs + Log FAB (Metric/Workout/Food) + reminder re-sync.
- `home_screen.dart` — overall card, **coach-pinned insights**, body graph, metric grids. *Largest file (734 lines) — candidate to split.*
- `progress_screen.dart` — category cards → graph page + correlation. *Largest UI; could extract the chart widget.*
- `habits_screen.dart` — accountability + planner + weekly + calendar.
- `coach_screen.dart` — AI chat, suggested prompts, agentic Apply cards, "What I see" context sheet.
- `profile_screen.dart` — profile form + share-rank + Friends section.
- `metric_detail_sheet.dart` — rank, tier ladder, history, log form.
- `diet_screen.dart` / `workout_screen.dart` — the two logging flows.
- `body_graph.dart` (CustomPainter + hit-test) · `badge.dart` (SVG medallions) · `cloud_sheet.dart` (sign-in + sync).
- `main.dart` — entry; loads repo, fires notification setup, runs app.

**Backend (`backend/app/`)**
- `main.py` (app + routers + CORS), `config.py` (env settings), `db.py` (engine/session), `models.py` (User/Profile/Sample/Friendship/GoogleHealthToken), `schemas.py` (Pydantic), `engine.py` (imports the canonical engine), `ranking.py` (samples→ranks), `registry.py` (ranked categories), `jobs.py` (scheduled sync), `auth.py` (JWT + current_user), `coach.py` (context + system prompt + action parser).
- `routers/` — `auth, health, legal, profile, ranks, samples, friends, coach`.
- `integrations/google_health/` — `oauth, client, mapping, router`. *Improve: confirm steps/active-zone/energy type names + deeper sleep fields via `/debug`; auto "exercises"/energy pull.*
- `integrations/gemini/client.py` — Gemini call. *Improve: streaming; true function-calling; model fallback.*

**Tests** — `test/` (9 Dart: engine parity, system-verification, habits, profile, diet/workout, correlation, notifications, sync, all-tabs smoke) + `backend/tests/` (8: engine, auth, samples, ranks, google_health, friends, coach, + conftest).

**Config / docs** — `pubspec.yaml`, `analysis_options.yaml`, `codemagic.yaml` (TestFlight), `railway.json` (deploy), `backend/Dockerfile`, `backend/DEPLOY.md`, `backend/VERIFICATION.md`, `GUIDE.md`, `ARCHITECTURE.md`, `All readmes/` (design docs + the PDF + STATUS/STANDARDS).
