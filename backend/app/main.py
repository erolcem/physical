"""Physical backend — FastAPI app.

Canonical sample store + rank API. The rank math is the shared
`physical_rank_engine.py` (same source the Flutter app ports), so ranks computed
here match the client exactly.

Run:  uvicorn app.main:app --reload      (from the backend/ directory)
Docs: http://localhost:8000/docs
"""
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.responses import RedirectResponse

from .db import init_db
from .integrations.fitbit.router import router as fitbit_router
from .routers import health, profile, ranks, samples


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


app = FastAPI(title="Physical Backend", version="0.1.0", lifespan=lifespan)


@app.get("/", include_in_schema=False)
def root():
    # The backend is a headless API — send browsers to the interactive docs.
    return RedirectResponse(url="/docs")


app.include_router(health.router)
app.include_router(profile.router)
app.include_router(samples.router)
app.include_router(ranks.router)
app.include_router(fitbit_router)
