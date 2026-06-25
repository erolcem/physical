# Physical — Architecture

A complete map of the system: every layer, how data flows, and where each feature
from the plan lives. Companion to `GUIDE.md` (usage), `backend/DEPLOY.md` (hosting),
`backend/VERIFICATION.md` (Google review), and `All readmes/` (the design docs + PDF).

**Status:** the **entire plan (Parts 1–7, AI coach included)** is implemented.
100 Flutter tests + 44 backend tests green, 0 analyzer issues, Python⇄Dart engine
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
  nothing changes without the user's tap.

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

## 7. Tests (144 total)
- **Flutter (100):** engine parity vs golden vectors, system-verification
  (registry↔engine, PDF categories, every lift ranks, directions, overall/category),
  habits (streaks/verification/planner/weekly/calendar), profile, sync, and an
  **all-tabs runtime smoke test** (now 5 tabs incl. Coach).
- **Backend (44):** engine load + coverage, auth, samples (incl. isolation
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
