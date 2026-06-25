"""Friends flow: request → accept → see overall rank; privacy (no rank until
accepted), self-add guard, and removal."""
from .conftest import auth_header


def _signin(client, uid):
    return auth_header(client, uid)  # creates the dev user + returns Bearer header


def test_request_accept_and_see_rank(client):
    alice = _signin(client, "alice")
    bob = _signin(client, "bob")

    # Bob logs a lift so he has an overall rank.
    client.post("/me/samples", headers=bob, json=[
        {"metric_id": "bench", "ts": "2026-06-01T08:00:00", "bodyweight_at_ts": 80,
         "value": 100, "source": "manual", "source_id": "b1"}])

    # Alice requests Bob by email.
    r = client.post("/me/friends", headers=alice, json={"email": "bob@dev.local"})
    assert r.status_code == 200 and r.json()["status"] == "pending"

    # Not accepted yet → Alice has no friends, Bob has a pending request.
    assert client.get("/me/friends", headers=alice).json() == []
    pend = client.get("/me/friends/requests", headers=bob).json()
    assert len(pend) == 1 and pend[0]["requester_id"] == "alice"

    # Bob accepts.
    assert client.post("/me/friends/alice/accept", headers=bob).status_code == 200

    # Now Alice sees Bob with an overall rank.
    friends = client.get("/me/friends", headers=alice).json()
    assert len(friends) == 1
    assert friends[0]["user_id"] == "bob"
    assert friends[0]["rank"]["tier"]  # has a tier from his bench log


def test_cannot_add_self_or_unknown_email(client):
    alice = _signin(client, "alice")
    assert client.post("/me/friends", headers=alice,
                       json={"email": "alice@dev.local"}).status_code == 400
    assert client.post("/me/friends", headers=alice,
                       json={"email": "ghost@nowhere.com"}).status_code == 404


def test_remove_friend(client):
    alice = _signin(client, "alice")
    _signin(client, "bob")
    client.post("/me/friends", headers=alice, json={"email": "bob@dev.local"})
    bob = auth_header(client, "bob")
    client.post("/me/friends/alice/accept", headers=bob)
    assert len(client.get("/me/friends", headers=alice).json()) == 1
    client.delete("/me/friends/bob", headers=alice)
    assert client.get("/me/friends", headers=alice).json() == []


def test_friends_require_auth():
    from fastapi.testclient import TestClient
    from app.main import app
    with TestClient(app) as c:
        assert c.get("/me/friends").status_code == 401
