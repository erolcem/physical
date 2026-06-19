def test_ingest_and_list(client):
    r = client.post("/users/u1/samples", json=[
        {"metric_id": "bench", "ts": "2026-06-01T08:00:00", "value": 100, "bodyweight_at_ts": 80},
        {"metric_id": "vo2max", "ts": "2026-06-01T08:00:00", "value": 50},
    ])
    assert r.status_code == 200
    assert r.json()["ingested"] == 2
    assert len(client.get("/users/u1/samples").json()) == 2


def test_dedup_by_source_id(client):
    payload = [{"metric_id": "steps", "ts": "2026-06-01T00:00:00", "value": 9000,
                "source": "fitbit", "source_id": "2026-06-01"}]
    assert client.post("/users/u1/samples", json=payload).json()["ingested"] == 1
    again = client.post("/users/u1/samples", json=payload).json()
    assert again["ingested"] == 0 and again["skipped"] == 1
    # Still only one stored.
    assert len(client.get("/users/u1/samples", params={"metric_id": "steps"}).json()) == 1


def test_manual_logs_without_source_id_always_insert(client):
    s = {"metric_id": "vo2max", "ts": "2026-06-01T08:00:00", "value": 48}
    client.post("/users/u1/samples", json=[s])
    client.post("/users/u1/samples", json=[s])  # no source_id ⇒ no dedup
    assert len(client.get("/users/u1/samples", params={"metric_id": "vo2max"}).json()) == 2


def test_est_1rm_from_raw_weight_reps(client):
    r = client.post("/users/u1/samples", json=[
        {"metric_id": "bench", "ts": "2026-06-01T08:00:00", "bodyweight_at_ts": 80,
         "raw": {"weight": 100, "reps": 5}},
    ])
    assert r.status_code == 200
    stored = client.get("/users/u1/samples", params={"metric_id": "bench"}).json()[0]
    assert stored["value"] > 100  # 1RM estimate from 100×5 exceeds 100


def test_value_required_when_no_raw(client):
    r = client.post("/users/u1/samples", json=[
        {"metric_id": "bench", "ts": "2026-06-01T08:00:00", "bodyweight_at_ts": 80},
    ])
    assert r.status_code == 422


def test_profile_upsert_and_get(client):
    client.put("/users/u1/profile", json={"sex": "male", "age": 25, "height_cm": 180})
    p = client.get("/users/u1/profile").json()
    assert p["age"] == 25 and p["user_id"] == "u1"
    assert client.get("/users/ghost/profile").status_code == 404
