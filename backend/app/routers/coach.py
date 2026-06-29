"""AI coach (PDF Part 5). The model sees the user's real canonical data (ranks +
recent readings) plus app-supplied habits/profile, all PII-scrubbed, and replies
as a coach. Powered by Gemini to stay in the user's Google ecosystem."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..auth import current_user
from ..coach import (ACTION_TOOLS, actions_from_calls, compose_system,
                     context_sections, dedupe_actions, parse_actions)
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
        reply, calls = gemini.generate_full(system, turns, tools=ACTION_TOOLS)
    except gemini.GeminiError as e:
        raise HTTPException(502, f"Coach unavailable: {e}")
    # Actions can arrive as tool calls (preferred) or ```action blocks (fallback).
    clean, fenced = parse_actions(reply)
    actions = dedupe_actions(actions_from_calls(calls) + fenced)
    # If the model only called a tool with no prose, give the bubble a short line.
    if not clean and actions:
        clean = "Here's a change I'd suggest — tap to apply."
    return CoachChatOut(reply=clean, actions=actions)


_NUDGE = ("Based ONLY on the USER DATA, write the single most useful one-sentence push "
          "notification to send this user — specific and motivating, grounded in their data "
          "(readiness, a missed habit target, their weakest area, a streak, or a notable "
          "trend). Max 130 characters, plain text, no markdown, no quotes, no emoji. "
          "Output ONLY that sentence.")
_SLOTS = {
    "morning": " Frame it for the MORNING: the day ahead — what to prioritise + the plan.",
    "evening": " Frame it for the EVENING: reflect on how today went — what was hit/missed.",
}


@router.post("/nudge")
def nudge(body: CoachChatIn,
          user_id: str = Depends(current_user),
          db: Session = Depends(get_db)):
    """A short, AI-personalised notification line from the user's live context. The slot
    ('morning'/'evening', passed in `message`) frames it forward- or backward-looking."""
    if not gemini.configured():
        raise HTTPException(503, "AI coach isn't configured on the server yet")
    samples = list(db.scalars(select(Sample).where(Sample.user_id == user_id)))
    system = compose_system(samples, body.habits, body.profile, body.diet, body.training,
                            body.aesthetics, body.ranks, body.trends, body.correlations,
                            body.workout_sets)
    instruction = _NUDGE + _SLOTS.get((body.message or "").strip().lower(), "")
    try:
        reply = gemini.generate(system, [{"role": "user", "text": instruction}])
    except gemini.GeminiError as e:
        raise HTTPException(502, f"Coach unavailable: {e}")
    line = (reply or "").strip().splitlines()[0].strip().strip('"').strip() if reply else ""
    return {"nudge": line[:160]}
