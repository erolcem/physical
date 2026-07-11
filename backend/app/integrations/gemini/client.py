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


def _turn_parts(t: dict) -> list[dict]:
    """A turn's content parts: its text, plus an optional inline image
    (`image_b64` + `image_mime`) for multimodal turns (e.g. a meal photo
    alongside the food description). Tool-loop replay turns instead carry
    `fn_calls` (a model turn's functionCalls) or `fn_responses` (the user
    turn answering them) — Gemini requires each call paired with a response
    in the following turn."""
    parts: list[dict] = []
    if t.get("text") or not (t.get("fn_calls") or t.get("fn_responses")):
        parts.append({"text": t.get("text", "")})
    for c in t.get("fn_calls") or []:
        parts.append({"functionCall": {"name": c["name"], "args": c.get("args") or {}}})
    for r in t.get("fn_responses") or []:
        parts.append({"functionResponse": {"name": r["name"],
                                           "response": r.get("response") or {}}})
    if t.get("image_b64"):
        parts.append({"inline_data": {
            "mime_type": t.get("image_mime") or "image/jpeg",
            "data": t["image_b64"],
        }})
    return parts


def _build(system: str, turns: list[dict], temperature: float,
           tools: list[dict] | None, minimal: bool, model: str) -> dict:
    # Pro-class models think by default (and reject a zero budget), so they get a
    # large output window that leaves room for thinking + a full reply. Flash gets
    # thinking dialled down so thinking tokens don't eat the output budget (which
    # used to return finishReason=MAX_TOKENS with NO text) — the prompt reasons
    # explicitly. Gemini 2.x flash takes a numeric thinkingBudget; Gemini 3+
    # replaced it with thinkingLevel (a zero budget is rejected there). A wrong
    # field only costs the rich tier — the minimal retry below drops it.
    is_flash = "flash" in model or "lite" in model
    gen: dict = {"temperature": temperature,
                 "maxOutputTokens": 1536 if minimal else (4096 if is_flash else 8192)}
    if not minimal and is_flash:
        if model.startswith("gemini-2"):
            gen["thinkingConfig"] = {"thinkingBudget": 0}
        else:
            gen["thinkingConfig"] = {"thinkingLevel": "low"}
    body: dict = {
        "system_instruction": {"parts": [{"text": system}]},
        "contents": [{"role": t["role"], "parts": _turn_parts(t)} for t in turns],
        "generationConfig": gen,
    }
    if tools and not minimal:
        body["tools"] = [{"functionDeclarations": tools}]
        body["toolConfig"] = {"functionCallingConfig": {"mode": "AUTO"}}
    return body


def _call(system: str, turns: list[dict], *, model: str | None = None,
          temperature: float = 0.5, tools: list[dict] | None = None) -> list[dict]:
    """POST generateContent and return the first candidate's content parts.

    Degrades gracefully: if the rich request (thinkingConfig + tools) is rejected with a
    400 (some models/regions don't accept those fields), it retries a PLAIN request so the
    coach still answers — losing function-calling, not the reply. Raises GeminiError only
    when even the plain request fails."""
    if not configured():
        raise GeminiError("AI coach is not configured (GEMINI_API_KEY unset)")
    mdl = model or settings.gemini_model
    url = f"{BASE}/models/{mdl}:generateContent?key={settings.gemini_api_key}"
    last_err = "unknown"
    # Tier 1 = full (tools + tuned thinking); tier 2 = minimal (plain text) as a fallback.
    for minimal in (False, True):
        body = _build(system, turns, temperature, tools, minimal, mdl)
        for _ in range(2):  # transient retry within a tier
            try:
                r = httpx.post(url, json=body, timeout=60)
            except Exception as e:  # network / timeout
                last_err = f"request failed: {str(e)[:160]}"
                continue
            if r.status_code == 400:
                last_err = f"Gemini 400: {r.text[:200]}"
                break  # bad request for THIS config — drop to the minimal tier
            if r.status_code == 404 and mdl != settings.gemini_fast_model:
                # This key/region can't use the requested (Pro-class) model — degrade
                # to the fast model rather than failing the whole reply.
                return _call(system, turns, model=settings.gemini_fast_model,
                             temperature=temperature, tools=tools)
            if r.status_code >= 500:
                last_err = f"Gemini {r.status_code}"
                continue
            if r.status_code >= 400:
                raise GeminiError(f"Gemini {r.status_code}: {r.text[:300]}")
            data = r.json()
            cands = data.get("candidates") or []
            if cands and cands[0].get("content", {}).get("parts"):
                return cands[0]["content"]["parts"]
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
