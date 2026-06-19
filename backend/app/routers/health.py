from fastapi import APIRouter

from .. import engine as E

router = APIRouter(tags=["meta"])


@router.get("/health")
def health():
    return {
        "status": "ok",
        "engine_metrics": len(E.STANDARDS),
        "tiers": E.TIERS,
    }
