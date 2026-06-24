"""Authentication: issue/verify our own JWTs, and a FastAPI dependency that
resolves the current user from a Bearer token. Identity comes from Google
Sign-In (verified id_token) in production, or the dev sign-in for local work.
"""
import datetime as dt

import jwt
from fastapi import Header, HTTPException

from .config import settings

_ALGO = "HS256"


def create_access_token(user_id: str) -> str:
    payload = {
        "sub": user_id,
        "iat": dt.datetime.now(dt.timezone.utc),
        "exp": dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=settings.jwt_expire_days),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=_ALGO)


def current_user(authorization: str | None = Header(default=None)) -> str:
    """Dependency → the authenticated user_id. 401 if missing/invalid.
    Every per-user endpoint depends on this, so data is always scoped to the
    caller (no cross-user access)."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="missing bearer token")
    token = authorization.split(" ", 1)[1]
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[_ALGO])
    except jwt.PyJWTError:
        raise HTTPException(status_code=401, detail="invalid or expired token")
    return payload["sub"]
