"""LLM habit verification endpoint. The app sends the day's habits + evidence;
Gemini (fast model) judges each one — see habit_check.py for the rules."""
from fastapi import APIRouter, Depends, HTTPException

from ..auth import current_user
from ..config import settings
from ..habit_check import VERIFY_PROMPT, build_evidence, parse_verdicts
from ..integrations.gemini import client as gemini
from ..schemas import HabitVerifyIn, HabitVerifyOut

router = APIRouter(prefix="/me/habits", tags=["habits"])


@router.get("/verify/status")
def status():
    return {"configured": gemini.configured()}


@router.post("/verify", response_model=HabitVerifyOut)
def verify(body: HabitVerifyIn, user_id: str = Depends(current_user)):
    if not gemini.configured():
        raise HTTPException(503, "AI verification isn't configured on the server yet")
    habits = [h for h in body.habits if isinstance(h, dict) and h.get("id")]
    if not habits:
        return HabitVerifyOut(verdicts=[], model=settings.gemini_fast_model)
    payload = build_evidence(body.day, habits, body.workouts, body.food, body.metrics)
    try:
        reply = gemini.generate(VERIFY_PROMPT, [{"role": "user", "text": payload}],
                                model=settings.gemini_fast_model, temperature=0.1)
    except gemini.GeminiError as e:
        raise HTTPException(502, f"Verification unavailable: {e}")
    verdicts = parse_verdicts(reply, [str(h["id"]) for h in habits])
    return HabitVerifyOut(verdicts=verdicts, model=settings.gemini_fast_model)
