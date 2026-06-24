"""Public legal pages — a privacy policy and terms, served as plain HTML so they
have a real, linkable URL (needed for Google OAuth verification AND the App
Store). The Google "Limited Use" disclosure is included verbatim because
restricted-scope verification requires it.

URLs once hosted:
  https://<your-host>/privacy
  https://<your-host>/terms
"""
from datetime import date

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

from ..config import settings

router = APIRouter(tags=["legal"])

_UPDATED = date.today().isoformat()

_STYLE = (
    "<style>body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:760px;"
    "margin:40px auto;padding:0 20px;line-height:1.6;color:#1a1a2e}"
    "h1{font-size:1.6rem}h2{font-size:1.15rem;margin-top:1.8em}"
    "code{background:#f0f0f5;padding:1px 5px;border-radius:4px}"
    ".muted{color:#666;font-size:.9rem}</style>"
)


def _page(title: str, body: str) -> str:
    return (f"<!doctype html><html><head><meta charset='utf-8'>"
            f"<meta name='viewport' content='width=device-width, initial-scale=1'>"
            f"<title>{title} · {settings.app_name}</title>{_STYLE}</head>"
            f"<body>{body}<hr><p class='muted'>{settings.app_name} · "
            f"Contact: <a href='mailto:{settings.contact_email}'>{settings.contact_email}</a></p>"
            f"</body></html>")


@router.get("/privacy", response_class=HTMLResponse, include_in_schema=False)
def privacy():
    app = settings.app_name
    body = f"""
<h1>{app} — Privacy Policy</h1>
<p class="muted">Last updated: {_UPDATED}</p>

<p>{app} is a personal fitness-ranking app. This policy explains what data it
handles, why, and your control over it.</p>

<h2>What we collect</h2>
<ul>
  <li><b>Google account identity</b> — your Google account id and email, used
      solely to create and secure your private account.</li>
  <li><b>Health &amp; fitness data from Google Health</b> (with your explicit
      consent) — e.g. resting heart rate, heart-rate variability, VO₂ max, sleep,
      and body measurements. Used to compute your fitness ranks and charts.</li>
  <li><b>Data you enter yourself</b> — workout, body-weight and similar logs.</li>
</ul>

<h2>How we use it</h2>
<p>Your data is used only to provide the app's features to you: computing your
ranks, trends and charts. We do <b>not</b> sell it, use it for advertising, or
share it with third parties.</p>

<h2>Google API Services Limited Use</h2>
<p>{app}'s use and transfer of information received from Google APIs to any other
app will adhere to the
<a href="https://developers.google.com/terms/api-services-user-data-policy">Google
API Services User Data Policy</a>, including the <b>Limited Use</b> requirements.
We do not use Google Health data for advertising, do not sell it, and do not allow
humans to read it except (a) with your consent, (b) for security/abuse/legal
reasons, or (c) where the data is aggregated/anonymized for internal operations.</p>

<h2>Storage &amp; security</h2>
<p>Data is stored in a private database on a hosted server, transmitted over
encrypted HTTPS, and isolated per account so no user can see another's data.</p>

<h2>Retention &amp; deletion</h2>
<p>You can revoke {app}'s access at any time in your
<a href="https://myaccount.google.com/permissions">Google account permissions</a>.
To delete your account and all associated data, email
<a href="mailto:{settings.contact_email}">{settings.contact_email}</a> and we will
delete it promptly.</p>

<h2>Changes</h2>
<p>We may update this policy; material changes will be reflected by the date above.</p>
"""
    return _page("Privacy Policy", body)


@router.get("/terms", response_class=HTMLResponse, include_in_schema=False)
def terms():
    app = settings.app_name
    body = f"""
<h1>{app} — Terms of Service</h1>
<p class="muted">Last updated: {_UPDATED}</p>
<p>{app} is provided as-is for personal fitness tracking. It is not a medical
device and does not provide medical advice; do not rely on it for diagnosis or
treatment. By using {app} you consent to the data handling described in our
<a href="/privacy">Privacy Policy</a>. You are responsible for the accuracy of
data you enter and for maintaining the security of your Google account. We may
modify or discontinue the service at any time.</p>
"""
    return _page("Terms of Service", body)
