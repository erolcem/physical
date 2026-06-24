# Physical — long-term usage guide

How to run, use, and ship Physical day-to-day. Three tracks: **Linux dev**,
**iPhone via TestFlight**, and **public App Store release**.

Your setup at a glance:
- App: Flutter (local-first; ranks compute on-device, cloud sync is opt-in).
- Backend: hosted on Railway — `https://physical-production-883c.up.railway.app`
  (always-on, Postgres). See `backend/DEPLOY.md`.
- Accounts/data: Google Sign-In = your account *and* your Google Health source.
- iOS builds: Codemagic cloud Mac → TestFlight (no Mac needed). See `codemagic.yaml`.

---

## 1. Linux dev mode (day-to-day)

Two ways to run, depending on what you're working on.

**A. Against the live cloud backend** (same data your iPhone sees):
```bash
flutter run -d linux --dart-define=BACKEND_URL=https://physical-production-883c.up.railway.app
```

**B. Against a local backend** (when changing backend code — uses local SQLite, no
cloud writes):
```bash
# terminal 1 — the backend, auto-reloads on edits
cd backend && .venv/bin/uvicorn app.main:app --reload
# terminal 2 — the app (defaults to localhost:8000)
flutter run -d linux
```

In the running app: `r` hot-reload · `R` hot-restart · `q` quit. Tap **☁** →
**Sign in with Google** → **Sync now**. Ranks are computed locally; sync mirrors
data to/from the cloud store.

**Checks before committing:**
```bash
flutter analyze && flutter test
cd backend && PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 .venv/bin/python -m pytest -q
```

**Ship backend changes:** `git push` → Railway auto-redeploys. (App-only changes
don't need a redeploy; rebuild the app instead.)

**Where data lives:** Linux app keeps a local copy (shared_preferences); the cloud
truth is Railway Postgres — it persists no matter which device is on.

---

## 2. iPhone via TestFlight (the everyday "no-laptop" path)

**One-time setup**
1. On the iPhone: install **TestFlight** from the App Store.
2. In **App Store Connect → your app → TestFlight → Internal Testing**, add your
   Apple ID as an internal tester. (Internal testers need no Beta App Review.)

**Each new version**
1. `git push`.
2. **Codemagic → `iOS · TestFlight` workflow → Start build** (~15–30 min). It signs,
   builds the IPA with the Railway URL baked in, and uploads to TestFlight.
3. Apple "processes" the build (a few minutes up to ~1 hour).
4. On the iPhone, open **TestFlight → Physical → Install/Update**.
5. In the app: **Sign in with Google → Sync**. You're on the cloud backend — no
   laptop involved.

**Long-term maintenance (important):**
- **TestFlight builds expire after 90 days.** To keep using it via TestFlight,
  push a fresh build at least once a quarter. (That's the only recurring chore.)
- **Keep the backend running.** Railway's trial credit is limited; for always-on
  long-term you'll likely move to their **Hobby plan (~$5/mo)**. Check usage in the
  Railway dashboard.
- **Google's 7-day token**: in Testing mode the Google Health link expires weekly.
  The app shows a one-tap **Reconnect Google Health** button when it does — that's
  the whole fix. (Removing it permanently needs verification; see `backend/VERIFICATION.md`.)

TestFlight is free with the $99/yr Apple Developer Program and supports up to 100
internal testers — plenty for personal/family use indefinitely.

---

## 3. Public App Store release

Only needed if **strangers** will install it. For personal/family use, TestFlight
(Section 2) is enough forever. The public path adds real requirements:

**In App Store Connect (the listing):**
- Screenshots (6.7" iPhone at minimum), description, keywords, category
  (Health & Fitness), support URL.
- **Privacy policy URL**: `https://physical-production-883c.up.railway.app/privacy`
  (already served by the backend).
- **App Privacy questionnaire** ("nutrition label"): declare Health & Fitness data
  + identifiers, linked to the user's identity, used for app functionality (not
  tracking / not ads).
- Age rating; export compliance (standard HTTPS → usually "exempt").

**Likely code/work before it passes review:**
- **Guideline 4.8 — Sign in with Apple.** Because the app offers Google sign-in,
  Apple generally requires offering an equivalent privacy-preserving option. Plan
  to **add "Sign in with Apple"** alongside Google. (Real work — budget for it.)
- **Google OAuth verification + CASA** (`backend/VERIFICATION.md`). For an unrestricted
  public audience without the "unverified app" consent warning, the restricted
  health scopes need Google's verification *and* the paid annual CASA security audit.
  This is the main gate for a public health-data app.
- HealthKit is **not** used (we use cloud Google Health), so there's nothing to
  justify there — optionally disable the unused HealthKit capability on the App ID
  to avoid reviewer questions.

**Submit & maintain:**
- Bump `version:` in `pubspec.yaml` for each public release (build number
  auto-increments in CI). Build via the same Codemagic workflow.
- App Store Connect → select the build → **Submit for Review** (Apple review
  ~1–3 days). Each future update is a new build + (usually light) re-review.

---

## TL;DR
- **Develop**: `flutter run -d linux --dart-define=BACKEND_URL=…railway.app`.
- **Use on iPhone**: push → Codemagic build → TestFlight → install → Google sign-in.
  Re-build quarterly (90-day expiry); keep Railway running (~$5/mo long-term).
- **Go public**: add Sign in with Apple + complete Google verification/CASA, fill
  the App Store listing + privacy questionnaire, submit for review.
