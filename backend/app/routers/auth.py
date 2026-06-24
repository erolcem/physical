"""Sign-in endpoints. Google Sign-In is the real path (verifies a Google
id_token → upserts the user → issues our JWT). /auth/dev is a local-only
password-less sign-in for development."""
import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ..auth import create_access_token, current_user
from ..config import settings
from ..db import get_db
from ..models import User

router = APIRouter(prefix="/auth", tags=["auth"])


class TokenOut(BaseModel):
    access_token: str
    user_id: str
    email: str | None = None


class GoogleSignIn(BaseModel):
    id_token: str


def _issue(db: Session, user_id: str, email: str | None, name: str | None) -> TokenOut:
    user = db.get(User, user_id) or User(id=user_id)
    user.email, user.name = email, name
    db.merge(user)
    db.commit()
    return TokenOut(access_token=create_access_token(user_id), user_id=user_id, email=email)


@router.post("/google", response_model=TokenOut)
def google_signin(body: GoogleSignIn, db: Session = Depends(get_db)):
    """Verify a Google id_token (from Google Sign-In on the device) and sign the
    user in. The Google account's stable `sub` becomes their user_id."""
    r = httpx.get("https://oauth2.googleapis.com/tokeninfo",
                  params={"id_token": body.id_token}, timeout=15)
    if r.status_code != 200:
        raise HTTPException(status_code=401, detail="invalid Google id_token")
    info = r.json()
    if settings.google_client_id and info.get("aud") != settings.google_client_id:
        raise HTTPException(status_code=401, detail="id_token audience mismatch")
    return _issue(db, info["sub"], info.get("email"), info.get("name"))


class DevSignIn(BaseModel):
    user_id: str = "local-dev"


@router.post("/dev", response_model=TokenOut)
def dev_signin(body: DevSignIn, db: Session = Depends(get_db)):
    if not settings.allow_dev_auth:
        raise HTTPException(status_code=403, detail="dev auth is disabled")
    return _issue(db, body.user_id, f"{body.user_id}@dev.local", body.user_id)


@router.get("/me", response_model=TokenOut)
def me(user_id: str = Depends(current_user), db: Session = Depends(get_db)):
    user = db.get(User, user_id)
    return TokenOut(access_token="", user_id=user_id, email=user.email if user else None)
