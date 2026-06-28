"""Thin Gemini (Google Generative Language API) client. Kept in the Google
ecosystem so sign-in, Health, Calendar, and the coach all flow through the user's
Google account. The key comes from Google AI Studio.

Stateless `generate(...)` over the stable v1beta `generateContent` REST shape — a
system instruction + a list of conversation turns → the model's text reply.
"""
import httpx

from ...config import settings

BASE = "https://generativelanguage.googleapis.com/v1beta"


class GeminiError(RuntimeError):
    pass


def configured() -> bool:
    return bool(settings.gemini_api_key)


def generate(system: str, turns: list[dict], *, model: str | None = None,
             temperature: float = 0.5) -> str:
    """`turns` is [{"role": "user"|"model", "text": "..."}]. Returns the reply text.

    Raises GeminiError if the coach isn't configured or the API errors — callers
    translate that into a clean response for the app.
    """
    if not configured():
        raise GeminiError("AI coach is not configured (GEMINI_API_KEY unset)")
    mdl = model or settings.gemini_model
    body = {
        "system_instruction": {"parts": [{"text": system}]},
        "contents": [
            {"role": t["role"], "parts": [{"text": t["text"]}]} for t in turns
        ],
        "generationConfig": {"temperature": temperature, "maxOutputTokens": 2048},
    }
    url = f"{BASE}/models/{mdl}:generateContent?key={settings.gemini_api_key}"
    try:
        r = httpx.post(url, json=body, timeout=45)
    except Exception as e:  # network / timeout
        raise GeminiError(f"Gemini request failed: {str(e)[:200]}")
    if r.status_code >= 400:
        raise GeminiError(f"Gemini {r.status_code}: {r.text[:300]}")
    data = r.json()
    try:
        parts = data["candidates"][0]["content"]["parts"]
        return "".join(p.get("text", "") for p in parts).strip()
    except (KeyError, IndexError):
        # e.g. a safety block with no candidate content.
        raise GeminiError("Gemini returned no usable content")
