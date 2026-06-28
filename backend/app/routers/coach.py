"""AI coach (PDF Part 5). The model sees the user's real canonical data (ranks +
recent readings) plus app-supplied habits/profile, all PII-scrubbed, and replies
as a coach. Powered by Gemini to stay in the user's Google ecosystem."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..auth import current_user
from ..coach import compose_system, context_sections, parse_actions
from ..config import settings
from ..db import get_db
from ..integrations.gemini import client as gemini
from ..models import Sample
from ..schemas import CoachChatIn, CoachChatOut, CoachContextIn

router = APIRouter(prefix="/me/coach", tags=["coach"])


@router.get("/status")
def status():
    """Whether the coach is available (so the app can show a clean message)."""
    return {"configured": gemini.configured(),
            "model": settings.gemini_model if gemini.configured() else None}


@router.post("/context")
def context(body: CoachContextIn,
            user_id: str = Depends(current_user),
            db: Session = Depends(get_db)):
    """Exactly what the coach sees — for the transparency view. No model call."""
    samples = list(db.scalars(select(Sample).where(Sample.user_id == user_id)))
    return context_sections(samples, body.habits, body.profile,
                            body.diet, body.training, body.aesthetics,
                            body.ranks, body.trends, body.correlations, body.workout_sets)


@router.post("/chat", response_model=CoachChatOut)
def chat(body: CoachChatIn,
         user_id: str = Depends(current_user),
         db: Session = Depends(get_db)):
    if not gemini.configured():
        raise HTTPException(503, "AI coach isn't configured on the server yet")
    samples = list(db.scalars(select(Sample).where(Sample.user_id == user_id)))
    system = compose_system(samples, body.habits, body.profile,
                            body.diet, body.training, body.aesthetics,
                            body.ranks, body.trends, body.correlations, body.workout_sets)
    turns = [{"role": t.role, "text": t.text} for t in body.history]
    turns.append({"role": "user", "text": body.message})
    try:
        reply = gemini.generate(system, turns)
    except gemini.GeminiError as e:
        raise HTTPException(502, f"Coach unavailable: {e}")
    clean, actions = parse_actions(reply)
    return CoachChatOut(reply=clean, actions=actions)
