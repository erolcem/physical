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


def _call(system: str, turns: list[dict], *, model: str | None = None,
          temperature: float = 0.5, tools: list[dict] | None = None) -> list[dict]:
    """POST generateContent and return the first candidate's content parts.
    Raises GeminiError on config/network/API/safety problems."""
    if not configured():
        raise GeminiError("AI coach is not configured (GEMINI_API_KEY unset)")
    mdl = model or settings.gemini_model
    body: dict = {
        "system_instruction": {"parts": [{"text": system}]},
        "contents": [
            {"role": t["role"], "parts": [{"text": t["text"]}]} for t in turns
        ],
        "generationConfig": {
            "temperature": temperature,
            "maxOutputTokens": 2048,
            # Disable 2.5 "thinking" — otherwise thinking tokens can consume the whole
            # output budget and the model returns finishReason=MAX_TOKENS with NO text
            # (the intermittent "couldn't respond"). The prompt already reasons explicitly.
            "thinkingConfig": {"thinkingBudget": 0},
        },
    }
    if tools:
        body["tools"] = [{"functionDeclarations": tools}]
        body["toolConfig"] = {"functionCallingConfig": {"mode": "AUTO"}}
    url = f"{BASE}/models/{mdl}:generateContent?key={settings.gemini_api_key}"
    # Retry once on transient failures (network blip, 5xx, empty candidate).
    last_err = "unknown"
    for attempt in range(2):
        try:
            r = httpx.post(url, json=body, timeout=60)
        except Exception as e:  # network / timeout
            last_err = f"request failed: {str(e)[:160]}"
            continue
        if r.status_code >= 500:
            last_err = f"Gemini {r.status_code}"
            continue
        if r.status_code >= 400:
            raise GeminiError(f"Gemini {r.status_code}: {r.text[:300]}")  # 4xx won't fix on retry
        data = r.json()
        cands = data.get("candidates") or []
        if cands and cands[0].get("content", {}).get("parts"):
            return cands[0]["content"]["parts"]
        # No content — note the finish reason (SAFETY / MAX_TOKENS / RECITATION) and retry.
        last_err = f"no content ({cands[0].get('finishReason') if cands else 'no candidate'})"
    raise GeminiError(f"Gemini returned {last_err}")


def generate(system: str, turns: list[dict], *, model: str | None = None,
             temperature: float = 0.5) -> str:
    """`turns` is [{"role": "user"|"model", "text": "..."}]. Returns the reply text."""
    parts = _call(system, turns, model=model, temperature=temperature)
    return "".join(p.get("text", "") for p in parts).strip()


def generate_full(system: str, turns: list[dict], *, tools: list[dict] | None = None,
                  temperature: float = 0.5) -> tuple[str, list[dict]]:
    """Like generate, but also returns any function calls the model made (tool use):
    (reply_text, [{"name": str, "args": {...}}, ...])."""
    parts = _call(system, turns, temperature=temperature, tools=tools)
    text = "".join(p.get("text", "") for p in parts).strip()
    calls = [p["functionCall"] for p in parts if isinstance(p, dict) and "functionCall" in p]
    return text, calls
