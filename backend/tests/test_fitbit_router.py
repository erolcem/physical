"""Fitbit endpoints wire up and error-handle without hitting the live API."""


def test_sync_requires_a_connection(client):
    r = client.post("/integrations/fitbit/sync", params={"user_id": "u1"})
    assert r.status_code == 404  # not connected yet


def test_authorize_needs_client_id(client):
    # FITBIT_CLIENT_ID is unset in tests → a clear 500 rather than a broken redirect.
    r = client.get("/integrations/fitbit/authorize",
                   params={"user_id": "u1"}, follow_redirects=False)
    assert r.status_code == 500


def test_callback_rejects_unknown_state(client):
    r = client.get("/integrations/fitbit/callback",
                   params={"code": "abc", "state": "nope"})
    assert r.status_code == 400
