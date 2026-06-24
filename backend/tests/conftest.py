import os

# Transient in-memory module engine; every test overrides get_db with its own.
os.environ["DATABASE_URL"] = "sqlite://"

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db import Base, get_db
from app.main import app


@pytest.fixture
def client():
    eng = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool,
    )
    Base.metadata.create_all(eng)
    TestSession = sessionmaker(bind=eng, autoflush=False, autocommit=False)

    def _override():
        db = TestSession()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = _override
    with TestClient(app) as c:
        # Sign in as a dev user so the per-user (/me/*) routes are authenticated.
        tok = c.post("/auth/dev", json={"user_id": "local-dev"}).json()["access_token"]
        c.headers["Authorization"] = f"Bearer {tok}"
        yield c
    app.dependency_overrides.clear()


def auth_header(client, user_id: str) -> dict:
    """Bearer header for a specific dev user (for isolation tests)."""
    tok = client.post("/auth/dev", json={"user_id": user_id}).json()["access_token"]
    return {"Authorization": f"Bearer {tok}"}
