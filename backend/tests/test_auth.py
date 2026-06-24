"""Auth core: dev sign-in issues a JWT, /me requires it, bad/missing tokens 401."""


def test_dev_signin_issues_token_and_me_works(client):
    r = client.post("/auth/dev", json={"user_id": "alice"})
    assert r.status_code == 200
    tok = r.json()["access_token"]
    assert tok and r.json()["user_id"] == "alice"

    me = client.get("/auth/me", headers={"Authorization": f"Bearer {tok}"})
    assert me.status_code == 200 and me.json()["user_id"] == "alice"


def test_me_requires_a_token():
    # /me with no Authorization header → 401 (use a fresh client without auth).
    from fastapi.testclient import TestClient
    from app.main import app
    with TestClient(app) as c:
        assert c.get("/auth/me").status_code == 401
        assert c.get("/auth/me", headers={"Authorization": "Bearer nonsense"}).status_code == 401


def test_two_users_get_distinct_identities(client):
    a = client.post("/auth/dev", json={"user_id": "alice"}).json()["access_token"]
    b = client.post("/auth/dev", json={"user_id": "bob"}).json()["access_token"]
    ra = client.get("/auth/me", headers={"Authorization": f"Bearer {a}"}).json()
    rb = client.get("/auth/me", headers={"Authorization": f"Bearer {b}"}).json()
    assert ra["user_id"] == "alice" and rb["user_id"] == "bob"
