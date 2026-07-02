"""Nutrition inference (PDF Part 1 diet — macros + micronutrients). Estimates a
food's nutrition from its description via Gemini, so logging stays one line of text
and still yields micros. Powered by the same Gemini key as the coach."""
from fastapi import APIRouter, Depends, HTTPException

from ..auth import current_user
from ..config import settings
from ..integrations.gemini import client as gemini
from ..nutrition import NUTRITION_PROMPT, parse_nutrition
from ..schemas import NutritionIn, NutritionOut

router = APIRouter(prefix="/me/nutrition", tags=["nutrition"])


@router.get("/status")
def status():
    """Whether auto-fill is available (so the app shows/hides the button cleanly)."""
    return {"configured": gemini.configured()}


@router.post("", response_model=NutritionOut)
def infer(body: NutritionIn, user_id: str = Depends(current_user)):
    desc = (body.description or "").strip()
    if not desc:
        raise HTTPException(422, "Describe a food to estimate")
    if not gemini.configured():
        raise HTTPException(503, "Nutrition auto-fill isn't configured on the server yet")
    try:
        reply = gemini.generate(NUTRITION_PROMPT, [{"role": "user", "text": desc}],
                                model=settings.gemini_fast_model, temperature=0.2)
    except gemini.GeminiError as e:
        raise HTTPException(502, f"Couldn't estimate nutrition: {e}")
    data = parse_nutrition(reply)
    if data is None:
        raise HTTPException(502, "Couldn't estimate nutrition for that description")
    return NutritionOut(**data)
