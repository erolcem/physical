def test_backup_put_get_roundtrip(client):
    snap = {"v": 1, "logs": {"bench": [{"v": 100, "ts": "x"}]}, "food": [{"id": "f1"}]}
    r = client.put("/me/backup", json=snap)
    assert r.status_code == 200 and r.json()["bytes"] > 0
    got = client.get("/me/backup").json()
    assert got["data"] == snap
    assert "updated_at" in got


def test_backup_404_when_none(client):
    nobody = client.post("/auth/dev", json={"user_id": "nob"}).json()["access_token"]
    r = client.get("/me/backup", headers={"Authorization": f"Bearer {nobody}"})
    assert r.status_code == 404


def test_backup_last_write_wins(client):
    client.put("/me/backup", json={"a": 1})
    client.put("/me/backup", json={"a": 2})
    assert client.get("/me/backup").json()["data"] == {"a": 2}
