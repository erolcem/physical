# Google OAuth verification — groundwork

This is the prep for verifying Physical's **restricted** Google Health scopes. It
is intentionally *ready-to-submit but not submitted*: full verification also
requires an annual third-party **CASA security assessment** (paid, recurring),
which is overkill for personal use. Pursue this only when releasing publicly.

References:
- Restricted-scope verification — https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification
- Google Health app verification — https://developers.google.com/health/app-verification

Until then: stay in **Testing** mode (you + up to 100 testers). The only cost is
the 7-day token, which the app now handles with a one-tap **Reconnect Google
Health** prompt.

---

## 1. Prerequisites already in place
- **Privacy policy**: `https://<your-host>/privacy` (served by the backend; includes
  the required Google "Limited Use" disclosure).
- **Terms**: `https://<your-host>/terms`.
- Before submitting, set `CONTACT_EMAIL` (and optionally `APP_NAME`) env vars on the
  host so those pages show a real contact address.

## 2. OAuth consent screen (Google Cloud Console → APIs & Services → OAuth consent screen)
- **User type**: External.
- **App name**: Physical
- **User support email**: <your email>
- **App logo**: optional (a 120×120 PNG helps reviewers).
- **App domain / homepage**: your host URL.
- **Privacy policy URL**: `https://<your-host>/privacy`
- **Terms of service URL**: `https://<your-host>/terms`
- **Authorized domains**: the registrable domain of your host (e.g. `up.railway.app`
  cannot be verified — for production you'll want a custom domain you own, e.g.
  `physicalapp.com`, verified in Search Console).
- **Developer contact**: your email.

## 3. Scopes requested (all restricted) + justifications
Paste these as the per-scope justification when prompted. Each states *why the app
needs it* and *that data stays on-device-for-the-user only*.

| Scope | Justification |
|---|---|
| `…/auth/userinfo.email`, `…/auth/userinfo.profile`, `openid` | Create and secure the user's personal account; no other use. |
| `…/googlehealth.health_metrics_and_measurements.readonly` | Read resting heart rate, HRV, VO₂ max and body measurements to compute the user's own fitness percentile ranks and trend charts, shown only to that user. |
| `…/googlehealth.sleep.readonly` | Read sleep duration/efficiency/stages to compute the user's recovery metrics and charts, shown only to that user. |
| `…/googlehealth.activity_and_fitness.readonly` | Read activity/fitness data to compute the user's performance metrics, shown only to that user. |
| `…/googlehealth.profile.readonly` | Read basic health-profile attributes needed to normalize the above metrics (e.g. allometric body-weight scaling). |

**Limited Use statement** (reviewers look for this — it's verbatim on `/privacy`):
> Physical's use and transfer of information received from Google APIs adheres to
> the Google API Services User Data Policy, including the Limited Use requirements.
> Health data is used only to provide the user's own ranks and charts; it is never
> sold, used for ads, or shared with third parties.

## 4. Demo video (Google requires one for restricted scopes)
Screen-record, ~2 min, showing in this order:
1. The OAuth client id is visible (URL bar) on the Google consent screen.
2. Granting each requested scope on the consent screen.
3. The app immediately using that data — open the app, sync, and show the
   resting-HR / HRV / sleep ranks and charts populated from Google Health.
4. The data-deletion path: revoking access / the "delete my data" contact.

## 5. The CASA security assessment (the gate)
Restricted scopes require an **annual** assessment via Google's App Defense
Alliance (OWASP ASVS-based), performed by an authorized third-party assessor. It
confirms secure data handling and deletion-on-request. This is paid and recurring
— do it only when going public. When you do, the backend already supports the
deletion requirement (per-account data, deletable on request).

## 6. Submit
OAuth consent screen → **Publish app** → **Prepare for verification** → fill the
above → submit. Expect back-and-forth with the review team; the demo video and a
verifiable privacy-policy domain are the usual sticking points.
