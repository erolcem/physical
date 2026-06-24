# Deploying the backend (always-on cloud server)

The backend is just code; "hosting" runs it on a **cloud server** in a data
centre (rented from a host) — not your laptop, not your phone, not any device you
keep on. It runs 24/7, its **Postgres database persistently holds everything**
(account, samples, Google tokens, ranks), and a **scheduled job** keeps pulling
your Google Health data even when no device is open. Your phone is just a client
that connects when it's open.

The repo is deploy-ready: a `Dockerfile`, a DB-agnostic schema (auto-creates
tables on Postgres at startup), and a scheduled-sync entry point (`python -m
app.jobs`).

## Recommended: Railway (easiest)

1. **Push the repo to GitHub** (you're many commits ahead): `git push`.
2. **railway.app** → New Project → **Deploy from GitHub repo** → pick `physical`.
3. In the service **Settings → Build**: set **Dockerfile Path** = `backend/Dockerfile`
   (root build context — needed so the shared rank engine is included).
4. **Add Postgres**: in the project, **New → Database → PostgreSQL**. Railway
   exposes its connection string as `DATABASE_URL` — reference it on the service.
5. **Set environment variables** on the service:
   | Var | Value |
   |---|---|
   | `DATABASE_URL` | (from the Railway Postgres plugin) |
   | `JWT_SECRET` | a long random string (e.g. `openssl rand -hex 32`) |
   | `GOOGLE_CLIENT_ID` | your Google OAuth client id |
   | `GOOGLE_CLIENT_SECRET` | your Google OAuth client secret |
   | `GOOGLE_REDIRECT_URI` | `https://www.google.com` (keeps the paste flow) |
   | `ALLOW_DEV_AUTH` | `false` (disable the dev sign-in in production) |
6. **Deploy.** Railway builds the image and gives you a public URL like
   `https://physical-production.up.railway.app`. Check `…/health`.
7. **Scheduled sync**: add a second service / **Cron** in the same project running
   `python -m app.jobs` (e.g. every 3 hours). It refreshes everyone's data so it's
   ready before you even open the app.

(Render and Fly.io work the same way — point them at `backend/Dockerfile` with a
root build context, add managed Postgres, set the same env vars.)

## Point the app at it
Build the app against the hosted URL:
```bash
flutter build ipa --dart-define=BACKEND_URL=https://YOUR-APP.up.railway.app
# or, to try on Linux:
flutter run -d linux --dart-define=BACKEND_URL=https://YOUR-APP.up.railway.app
```
Now the iPhone reaches the server over the internet — no laptop required.

## Notes
- **Tables**: created automatically on first start (`Base.metadata.create_all`).
  For a TimescaleDB hypertable, see `scripts/timescale_init.sql` (optional).
- **Google's 7-day testing tokens** still apply until you complete Google's
  restricted-scope **security review** (production verification). Until then the
  scheduled sync works in 7-day windows and you re-sign-in weekly.
- **Local build sanity check**: from the repo root,
  `docker build -f backend/Dockerfile -t physical-backend . && docker run -p 8000:8000 physical-backend`.
