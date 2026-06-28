"""ICS subscription feed for habits. The user subscribes once (webcal://…) and their
timed habits show up as recurring calendar events that update on their own. The feed is
read without an interactive login, so it's protected by a stateless per-user token:
HMAC(user_id, jwt_secret) — unguessable, stable, and reversible to the user id."""
import base64
import datetime as dt
import hashlib
import hmac

from .config import settings

_BYDAY = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]


def feed_token(user_id: str) -> str:
    """A URL-safe, stable token encoding (and signing) the user id."""
    sig = hmac.new(settings.jwt_secret.encode(), user_id.encode(), hashlib.sha256).hexdigest()[:32]
    uid = base64.urlsafe_b64encode(user_id.encode()).decode().rstrip("=")
    return f"{uid}.{sig}"


def verify_token(token: str) -> str | None:
    """Return the user id if [token] is a valid feed token, else None."""
    try:
        uid_b64, sig = token.split(".", 1)
        pad = "=" * (-len(uid_b64) % 4)
        user_id = base64.urlsafe_b64decode(uid_b64 + pad).decode()
    except Exception:
        return None
    expected = hmac.new(settings.jwt_secret.encode(), user_id.encode(), hashlib.sha256).hexdigest()[:32]
    return user_id if hmac.compare_digest(sig, expected) else None


def _rrule(cadence: str, days: list) -> str:
    if cadence == "weekly" and days:
        byday = ",".join(_BYDAY[d - 1] for d in days if 1 <= d <= 7)
        return f"RRULE:FREQ=WEEKLY;BYDAY={byday}" if byday else "RRULE:FREQ=DAILY"
    return "RRULE:FREQ=DAILY"


def habit_event(h: dict, *, tz: str | None = None, now: dt.datetime | None = None) -> dict:
    """A Google Calendar API event body for a habit (recurring; tagged so re-pushes
    update rather than duplicate). Timed → a timed event in [tz]; untimed → all-day."""
    now = now or dt.datetime.now()
    title = str(h.get("title") or "Habit")
    section = str(h.get("cat") or h.get("section") or "misc")
    time = h.get("time")
    dur = int(h.get("dur") or h.get("durationMins") or 0)
    desc = f"Physical habit · {section}"
    if h.get("target") is not None:
        cmp = "≤" if (h.get("compare") or h.get("cmp")) == "lte" else "≥"
        t = h["target"]
        t = int(t) if float(t).is_integer() else t
        desc += f" · target {cmp} {t}{h.get('unit', '')}"
    if time:
        try:
            hh, mm = (int(x) for x in str(time).split(":")[:2])
        except Exception:
            hh, mm = 7, 0
        start = now.replace(hour=hh, minute=mm, second=0, microsecond=0)
        end = start + dt.timedelta(minutes=dur if dur > 0 else 30)
        tzkw = {"timeZone": tz} if tz else {}
        start_obj = {"dateTime": start.strftime("%Y-%m-%dT%H:%M:%S"), **tzkw}
        end_obj = {"dateTime": end.strftime("%Y-%m-%dT%H:%M:%S"), **tzkw}
    else:
        start_obj = {"date": now.strftime("%Y-%m-%d")}
        end_obj = {"date": (now + dt.timedelta(days=1)).strftime("%Y-%m-%d")}
    return {
        "summary": title,
        "description": desc,
        "start": start_obj,
        "end": end_obj,
        "recurrence": [_rrule(h.get("cadence") or "daily", h.get("days") or [])],
        "extendedProperties": {"private": {"app": "physical", "habit": str(h.get("id") or title)}},
    }


def _esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace(",", "\\,").replace(";", "\\;").replace("\n", " ")


def _fold(line: str) -> str:
    """Fold long lines to ≤75 octets per RFC 5545 (continuations begin with a space)."""
    out = []
    while len(line) > 73:
        out.append(line[:73])
        line = " " + line[73:]
    out.append(line)
    return "\r\n".join(out)


def build_ics(habits: list[dict], *, now: dt.datetime | None = None) -> str:
    """Build a VCALENDAR from the user's habit dicts (the app's Habit.toJson shape)."""
    now = now or dt.datetime.now()
    stamp = now.strftime("%Y%m%dT%H%M%S")
    lines = [
        "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Physical//Habits//EN",
        "CALSCALE:GREGORIAN", "METHOD:PUBLISH", "X-WR-CALNAME:Physical Habits",
        "REFRESH-INTERVAL;VALUE=DURATION:PT6H", "X-PUBLISHED-TTL:PT6H",
    ]
    for h in habits:
        title = _esc(str(h.get("title") or "Habit"))
        hid = str(h.get("id") or title)
        time = h.get("time")
        cadence = h.get("cadence") or "daily"
        days = h.get("days") or []
        dur = int(h.get("dur") or 0)
        section = str(h.get("cat") or "misc")

        if time:
            try:
                hh, mm = (int(x) for x in str(time).split(":")[:2])
            except Exception:
                hh, mm = 7, 0
            start = now.replace(hour=hh, minute=mm, second=0, microsecond=0)
            end = start + dt.timedelta(minutes=dur if dur > 0 else 30)
            dstart = f"DTSTART:{start.strftime('%Y%m%dT%H%M%S')}"
            dend = f"DTEND:{end.strftime('%Y%m%dT%H%M%S')}"
        else:
            # Untimed "anytime" habit → an all-day event so it still appears.
            dstart = f"DTSTART;VALUE=DATE:{now.strftime('%Y%m%d')}"
            dend = f"DTEND;VALUE=DATE:{(now + dt.timedelta(days=1)).strftime('%Y%m%d')}"

        rrule = _rrule(cadence, days)

        desc = f"Physical habit · {section}"
        if h.get("target") is not None:
            cmp = "≤" if h.get("cmp") == "lte" else "≥"
            t = h["target"]
            t = int(t) if float(t).is_integer() else t
            desc += f" · target {cmp} {t}{h.get('unit', '')}"

        lines += [
            "BEGIN:VEVENT", f"UID:{hid}@physical", f"DTSTAMP:{stamp}",
            dstart, dend, rrule,
            _fold(f"SUMMARY:{title}"), _fold(f"DESCRIPTION:{_esc(desc)}"),
            "END:VEVENT",
        ]
    lines.append("END:VCALENDAR")
    return "\r\n".join(lines) + "\r\n"
