# Physical — running it & turning on the AI coach (no code)

A plain-language guide: run the app, sign in with Google, switch on the Gemini AI
coach — all by clicking, no code editing — and the iPhone path for later.

The whole app lives in **your Google account**: sign-in, your Fitbit/Google Health
data, your calendar, and the AI (Gemini) all use the one Google login. The backend
already runs 24/7 in the cloud (Railway), so your phone/laptop don't need to stay on.

---

## A. Run it on Linux (for now, while iPhone is blocked)

You only need this once.

1. **Have Flutter installed** (you already develop on Linux, so this is set up). If a
   new machine: install Flutter, then `flutter doctor` until it's happy.
2. In a terminal, from the project folder:
   ```
   flutter run -d linux
   ```
   That's it — the app already points at the live cloud backend by default, so no
   flags or code needed. The Physical window opens.

*(Tip: `r` hot-reloads, `q` quits. Tabs along the top: Home · Progress · Habits ·
Coach.)*

---

## B. Sign in with Google (1 minute, in the app)

Signing in creates your private account **and** links your Google Health data in one
step.

1. Tap the **☁ cloud icon** (top-right) → the Cloud Sync sheet opens.
2. Tap **Sign in with Google**.
3. Your browser opens Google's consent page → approve.
4. You land on a `google.com` page with a code in the address bar → **copy that whole
   address (or just the code)** and paste it into the box in the app → **Sign in**.
5. It shows **"Signed in as &lt;your email&gt;"**. Tap **Sync now** to pull your data.

You stay signed in across restarts.

---

## C. Turn on the AI coach (Gemini) — no code

The coach needs one free key from Google. This is the only setup step.

1. Go to **[aistudio.google.com](https://aistudio.google.com)** and sign in with the
   **same Google account**.
2. Click **Get API key** → **Create API key** → **copy** it.
3. Go to your **Railway** project → the backend **service** → the **Variables** tab.
4. Add a variable:
   - **Name:** `GEMINI_API_KEY`  **Value:** *(paste the key)*
   - *(optional)* **Name:** `GEMINI_MODEL`  **Value:** `gemini-2.5-flash` (cheap + fast; the default)
5. Railway **redeploys automatically** (~1–2 min).

Done. Open the app's **Coach** tab — it switches from "not set up yet" to a live chat.
*(Gemini Flash is very cheap; a typical coaching message costs a fraction of a cent.)*

This **same key** also powers **diet auto-fill**: in **Diet → Log food**, type a food
(e.g. "2 eggs and toast") and tap **Auto-fill nutrition with AI** to fill calories,
macros, and micronutrients. Without the key you can still type the numbers in by hand.

---

## D. Use the coach

In the **Coach** tab:
- Tap a **suggested prompt** ("Review my training", "What should I improve?", "Plan
  my week", "Review my sleep & recovery") or just type.
- The coach already sees your **ranks, recent recovery, habits, today's diet, and
  last-7-day training** — so its advice is grounded in your real numbers.
- When it suggests a change, you get an **Apply** card (add/remove a habit, or pin a
  correlation to your dashboard) — nothing happens until you tap **Apply**.
- Tap **"What I see"** (top-right of the chat) to view the exact, sectioned context
  the coach holds — and confirm your email/name/id are never shared.

---

## E. On iPhone (once the Apple block is cleared)

The only thing stopping iPhone right now is the **Apple "Paid Apps" agreement** in
App Store Connect (Business → Agreements). Once that's **Active** (or Apple Support
clears it):

1. `git push` (so the latest is on GitHub).
2. **Codemagic** → start the **iOS · TestFlight** build (it already bakes in the cloud
   backend URL).
3. When it finishes processing, open **TestFlight** on your iPhone → **Install**.
4. In the app: **☁ → Sign in with Google → Sync**, then use the **Coach** tab.

Because the coach key lives on the *server*, the iPhone needs **no extra setup** — it
just works once you're signed in. Same for calendar and notifications
(the iPhone will ask for notification permission the first time).

---

## F. Send the developer your Google data (to wire the last auto-metrics) — no code

A few features (auto height/age, the workout↔Google-session check, deeper sleep
fields, exact step/energy field names) need to see the **real shape** of your Google
Health data. You can hand that over in 4 taps — no terminal:

1. Open the app (signed in) and tap the **☁ cloud icon**.
2. Tap **Sync now** once (so there's fresh Google data).
3. Tap **Inspect Google data** (next to "Sign out").
4. In the popup, tap **Copy**, then **paste it into the chat** to Claude.

That output is just numbers/shapes (heart rate, sleep stages, steps, etc.) — no
passwords or tokens. With it, the remaining auto-metrics get wired precisely instead
of guessed.

## Troubleshooting
- **Coach tab says "not set up yet"** → `GEMINI_API_KEY` isn't on Railway yet (step C),
  or the redeploy hasn't finished.
- **Sync says "couldn't reach the backend"** → check the backend is up at
  `…up.railway.app/health`; on a custom local build, pass
  `--dart-define=BACKEND_URL=…`.
- **Google sign-in token expired** (after ~7 days, while in Google "testing" mode) →
  the app shows a one-tap **Reconnect Google Health** button; tap it.
- **Every Google data type 403s with `DISALLOWED_OAUTH_SCOPES` (`cl_events`)** →
  the health token also carried the Calendar scope, which the Google Health API
  rejects outright. Health and Calendar are now TWO separate consents: tap
  **Reconnect Google Health** (health-only — fixes the 403s), then optionally
  **Connect Google Calendar** in the same Cloud sheet so habits auto-add to your
  calendar. On each Google consent page, tick **every** checkbox.
