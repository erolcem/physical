"""Aesthetics measurement endpoints. The app captures media and uploads it here;
the server runs the analysis (keeping any keys/heavy deps server-side) and returns a
0–100 clinical score for the user to log as the matching aesthetic metric.

  POST /me/aesthetics/voice   (multipart WAV) → {score, jitter_pct, shimmer_pct, hnr_db, ...}
"""
import os
import tempfile

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile

from ..aesthetics import voice
from ..auth import current_user

router = APIRouter(prefix="/me/aesthetics", tags=["aesthetics"])


@router.post("/voice")
async def measure_voice(file: UploadFile = File(...),
                        user_id: str = Depends(current_user)):
    """Analyze an uploaded voice clip (WAV) into a clinical 0–100 voice-quality score."""
    data = await file.read()
    if not data:
        raise HTTPException(422, "Empty audio upload")
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            tmp.write(data)
            tmp_path = tmp.name
        return voice.analyze(tmp_path)
    except ValueError as e:  # no voiced signal / unusable clip → user can re-record
        raise HTTPException(422, str(e))
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Voice analysis failed: {str(e)[:200]}")
    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)
