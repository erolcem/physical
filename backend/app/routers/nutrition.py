"""Nutrition inference (PDF Part 1 diet — macros + micronutrients). Estimates a
food's nutrition from its description via Gemini — optionally supplemented by a
meal PHOTO (text+photo is robust; the description is always required, never
photo-alone) — so logging stays one line of text and still yields micros.
Powered by the same Gemini key as the coach."""
from fastapi import APIRouter, Depends, HTTPException

from ..auth import current_user
from ..config import settings
from ..integrations.gemini import client as gemini
from ..nutrition import NUTRITION_PROMPT, PHOTO_HINT, parse_nutrition
from ..schemas import NutritionIn, NutritionOut

router = APIRouter(prefix="/me/nutrition", tags=["nutrition"])

# Base64 image ceiling (~4.5 MB decoded) — the app downscales to ≤1280px before
# sending, so anything bigger is a misbehaving client, not a real meal photo.
_MAX_IMAGE_B64 = 6_000_000


@router.get("/status")
def status():
    """Whether auto-fill is available (so the app shows/hides the button cleanly)."""
    return {"configured": gemini.configured()}


@router.post("", response_model=NutritionOut)
def infer(body: NutritionIn, user_id: str = Depends(current_user)):
    desc = (body.description or "").strip()
    if not desc:
        # The description is REQUIRED even with a photo: text+photo is robust,
        # photo-alone mis-identifies food too often to be trusted.
        raise HTTPException(422, "Describe the food — the photo only supplements the text")
    if not gemini.configured():
        raise HTTPException(503, "Nutrition auto-fill isn't configured on the server yet")
    image = (body.image_b64 or "").strip()
    if image.startswith("data:"):  # tolerate a data-URL from a web client
        image = image.split(",", 1)[-1]
    if len(image) > _MAX_IMAGE_B64:
        raise HTTPException(413, "Photo too large — retake or pick a smaller one")
    prompt = NUTRITION_PROMPT + (PHOTO_HINT if image else "")
    turn: dict = {"role": "user", "text": desc}
    if image:
        turn["image_b64"] = image
        turn["image_mime"] = body.image_mime or "image/jpeg"
    try:
        reply = gemini.generate(prompt, [turn],
                                model=settings.gemini_fast_model, temperature=0.2)
    except gemini.GeminiError as e:
        raise HTTPException(502, f"Couldn't estimate nutrition: {e}")
    data = parse_nutrition(reply)
    if data is None:
        raise HTTPException(502, "Couldn't estimate nutrition for that description")
    return NutritionOut(**data)
